/* pipewire-network-receiver.c
 *
 * Reads ~/.config/pipewire-network/receiver.json (fallback: /etc/pipewire-network/receiver.json),
 * starts an RTP source and auto-connects it to the system default output sink.
 * When the default sink changes the old links are torn down and new ones created.
 *
 * JSON config (all optional):
 *   { "port": 9875, "address": "0.0.0.0", "target_latency": 5 }
 *
 * Compile: see Makefile
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <stdbool.h>

#include <json-c/json.h>
#include <spa/utils/json.h>
#include <pipewire/pipewire.h>
#include <pipewire/impl.h>

/* ─── defaults ───────────────────────────────────────────────────────────── */
#define DEFAULT_PORT       9875
#define DEFAULT_ADDRESS    "0.0.0.0"
#define DEFAULT_LATENCY_MS 5
#define N_CHANNELS         2
#define MAX_NODES          256
#define MAX_PORTS          1024

/* ─── configuration ──────────────────────────────────────────────────────── */
struct config {
    int  port;
    char address[64];
    int  latency_ms;
};

static void config_defaults(struct config *c)
{
    c->port       = DEFAULT_PORT;
    c->latency_ms = DEFAULT_LATENCY_MS;
    strncpy(c->address, DEFAULT_ADDRESS, sizeof(c->address) - 1);
}

static int config_load(struct config *c, const char *path)
{
    struct json_object *root = json_object_from_file(path);
    if (!root) return -1;

    struct json_object *v;
    if (json_object_object_get_ex(root, "port", &v))
        c->port = json_object_get_int(v);
    if (json_object_object_get_ex(root, "address", &v))
        strncpy(c->address, json_object_get_string(v), sizeof(c->address) - 1);
    if (json_object_object_get_ex(root, "target_latency", &v))
        c->latency_ms = json_object_get_int(v);

    json_object_put(root);
    return 0;
}

static void config_load_best(struct config *c)
{
    config_defaults(c);
    const char *home = getenv("HOME");
    if (home) {
        char path[512];
        snprintf(path, sizeof(path), "%s/.config/pipewire-network/receiver.json", home);
        if (config_load(c, path) == 0) {
            fprintf(stderr, "[receiver] Config: %s\n", path);
            return;
        }
    }
    if (config_load(c, "/etc/pipewire-network/receiver.json") == 0) {
        fprintf(stderr, "[receiver] Config: /etc/pipewire-network/receiver.json\n");
        return;
    }
    fprintf(stderr, "[receiver] Using built-in defaults\n");
}

/* ─── cached registry objects ────────────────────────────────────────────── */
struct node_info { uint32_t id; char name[256]; };
struct port_info {
    uint32_t id, node_id, port_index;
    char direction[8];
    bool is_monitor;
};

/* ─── application state ──────────────────────────────────────────────────── */
struct app {
    struct pw_main_loop *loop;
    struct pw_context   *context;
    struct pw_core      *core;
    struct pw_registry  *registry;
    struct spa_hook      registry_listener;
    struct spa_hook      core_listener;

    struct pw_metadata  *metadata;
    struct spa_hook      metadata_listener;
    char default_sink_name[512];

    struct node_info nodes[MAX_NODES]; int n_nodes;
    struct port_info ports[MAX_PORTS]; int n_ports;

    struct pw_proxy *link_proxies[N_CHANNELS];
    int              n_link_proxies;
    bool links_created;
};

static void resolve(struct app *app);

/* ─── helpers ────────────────────────────────────────────────────────────── */
static void on_signal(void *data, int sig)
{
    (void)sig;
    pw_main_loop_quit(((struct app *)data)->loop);
}

static void on_core_error(void *data, uint32_t id, int seq, int res, const char *msg)
{
    struct app *app = data;
    (void)seq;
    fprintf(stderr, "[receiver] core error id=%u res=%d: %s\n", id, res, msg);
    if (id == PW_ID_CORE) pw_main_loop_quit(app->loop);
}

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS, .error = on_core_error
};

static void destroy_links(struct app *app)
{
    for (int i = 0; i < app->n_link_proxies; i++) {
        pw_proxy_destroy(app->link_proxies[i]);
        app->link_proxies[i] = NULL;
    }
    app->n_link_proxies = 0;
    app->links_created  = false;
}

/* ─── metadata ───────────────────────────────────────────────────────────── */
static int on_metadata_property(void *data, uint32_t subject,
                                const char *key, const char *type, const char *value)
{
    struct app *app = data;
    (void)subject; (void)type;
    if (!key || !value || strcmp(key, "default.audio.sink") != 0) return 0;

    /* Parse { "name": "<node-name>" } */
    struct spa_json it[2];
    char name_buf[512] = {0};
    spa_json_init(&it[0], value, strlen(value));
    if (spa_json_enter_object(&it[0], &it[1]) <= 0) return 0;
    char kbuf[64];
    while (spa_json_get_string(&it[1], kbuf, sizeof(kbuf)) > 0) {
        if (strcmp(kbuf, "name") == 0) {
            spa_json_get_string(&it[1], name_buf, sizeof(name_buf));
            break;
        } else {
            const char *tmp;
            if (spa_json_next(&it[1], &tmp) <= 0) break;
        }
    }
    if (name_buf[0] == '\0' || strcmp(app->default_sink_name, name_buf) == 0) return 0;

    strncpy(app->default_sink_name, name_buf, sizeof(app->default_sink_name) - 1);
    fprintf(stderr, "[receiver] Default sink: %s\n", app->default_sink_name);
    destroy_links(app);
    resolve(app);
    return 0;
}

static const struct pw_metadata_events metadata_events = {
    PW_VERSION_METADATA_EVENTS, .property = on_metadata_property
};

/* ─── resolve ────────────────────────────────────────────────────────────── */
static int cmp_pi(const void *a, const void *b)
{
    return (int)((const struct port_info *)a)->port_index
         - (int)((const struct port_info *)b)->port_index;
}

static void resolve(struct app *app)
{
    if (app->links_created) return;

    uint32_t src_id = SPA_ID_INVALID, snk_id = SPA_ID_INVALID;
    for (int i = 0; i < app->n_nodes; i++) {
        if (strcmp(app->nodes[i].name, "rtp-source") == 0)
            src_id = app->nodes[i].id;
        if (app->default_sink_name[0] &&
            strcmp(app->nodes[i].name, app->default_sink_name) == 0)
            snk_id = app->nodes[i].id;
    }
    if (src_id == SPA_ID_INVALID || snk_id == SPA_ID_INVALID) return;

    struct port_info sp[N_CHANNELS], dp[N_CHANNELS];
    int ns = 0, nd = 0;
    for (int i = 0; i < app->n_ports; i++) {
        struct port_info *p = &app->ports[i];
        if (p->node_id == src_id && strcmp(p->direction,"out")==0 && !p->is_monitor && ns < N_CHANNELS)
            sp[ns++] = *p;
        if (p->node_id == snk_id && strcmp(p->direction,"in")==0  && !p->is_monitor && nd < N_CHANNELS)
            dp[nd++] = *p;
    }
    if (ns < N_CHANNELS || nd < N_CHANNELS) return;

    qsort(sp, ns, sizeof(sp[0]), cmp_pi);
    qsort(dp, nd, sizeof(dp[0]), cmp_pi);

    fprintf(stderr, "[receiver] Linking rtp-source -> %s\n", app->default_sink_name);
    for (int i = 0; i < N_CHANNELS; i++) {
        struct pw_properties *lp = pw_properties_new(NULL, NULL);
        pw_properties_setf(lp, PW_KEY_LINK_OUTPUT_PORT, "%u", sp[i].id);
        pw_properties_setf(lp, PW_KEY_LINK_INPUT_PORT,  "%u", dp[i].id);
        pw_properties_set(lp, "link.passive", "false");
        struct pw_proxy *link = pw_core_create_object(app->core, "link-factory",
            PW_TYPE_INTERFACE_Link, PW_VERSION_LINK, &lp->dict, 0);
        pw_properties_free(lp);
        if (link) {
            app->link_proxies[app->n_link_proxies++] = link;
            fprintf(stderr, "[receiver] Link %d ok\n", i);
        } else {
            fprintf(stderr, "[receiver] Link %d failed: %m\n", i);
        }
    }
    app->links_created = true;
}

/* ─── registry ───────────────────────────────────────────────────────────── */
static void on_global(void *data, uint32_t id, uint32_t perms,
                      const char *type, uint32_t ver, const struct spa_dict *props)
{
    struct app *app = data;
    (void)perms; (void)ver;
    if (!props) return;

    if (strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0) {
        const char *n = spa_dict_lookup(props, PW_KEY_METADATA_NAME);
        if (!n || strcmp(n, "default") != 0 || app->metadata) return;
        app->metadata = pw_registry_bind(app->registry, id, type, PW_VERSION_METADATA, 0);
        if (app->metadata)
            pw_metadata_add_listener(app->metadata, &app->metadata_listener,
                                     &metadata_events, app);
        return;
    }
    if (strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
        const char *n = spa_dict_lookup(props, PW_KEY_NODE_NAME);
        if (!n || app->n_nodes >= MAX_NODES) return;
        app->nodes[app->n_nodes].id = id;
        strncpy(app->nodes[app->n_nodes].name, n, 255);
        app->n_nodes++;
        resolve(app);
        return;
    }
    if (strcmp(type, PW_TYPE_INTERFACE_Port) == 0) {
        const char *nid = spa_dict_lookup(props, "node.id");
        const char *dir = spa_dict_lookup(props, PW_KEY_PORT_DIRECTION);
        const char *pid = spa_dict_lookup(props, PW_KEY_PORT_ID);
        const char *mon = spa_dict_lookup(props, "port.monitor");
        if (!nid || !dir || !pid || app->n_ports >= MAX_PORTS) return;
        struct port_info *p = &app->ports[app->n_ports++];
        p->id = id;
        p->node_id    = (uint32_t)atoi(nid);
        p->port_index = (uint32_t)atoi(pid);
        strncpy(p->direction, dir, sizeof(p->direction) - 1);
        p->is_monitor = (mon && strcmp(mon, "true") == 0);
        resolve(app);
    }
}

static void on_global_remove(void *data, uint32_t id) { (void)data; (void)id; }

static const struct pw_registry_events registry_events = {
    PW_VERSION_REGISTRY_EVENTS, .global = on_global, .global_remove = on_global_remove
};

/* ─── main ───────────────────────────────────────────────────────────────── */
int main(int argc, char *argv[])
{
    struct config cfg;
    config_load_best(&cfg);

    fprintf(stderr, "[receiver] port=%d address=%s latency=%dms\n",
            cfg.port, cfg.address, cfg.latency_ms);

    struct app app = {0};
    int ret = 0;

    pw_init(&argc, &argv);

    app.loop = pw_main_loop_new(NULL);
    if (!app.loop) { ret = -errno; goto out_init; }

    {
        struct pw_loop *l = pw_main_loop_get_loop(app.loop);
        pw_loop_add_signal(l, SIGINT,  on_signal, &app);
        pw_loop_add_signal(l, SIGTERM, on_signal, &app);
    }

    app.context = pw_context_new(pw_main_loop_get_loop(app.loop), NULL, 0);
    if (!app.context) { ret = -errno; goto out_loop; }

    if (!pw_context_load_module(app.context, "libpipewire-module-link-factory", NULL, NULL)) {
        fprintf(stderr, "[receiver] Failed to load link-factory: %m\n");
        ret = -ENOENT; goto out_ctx;
    }

    app.core = pw_context_connect(app.context, NULL, 0);
    if (!app.core) { ret = -errno; goto out_ctx; }
    pw_core_add_listener(app.core, &app.core_listener, &core_events, &app);

    app.registry = pw_core_get_registry(app.core, PW_VERSION_REGISTRY, 0);
    if (!app.registry) { ret = -errno; goto out_core; }
    pw_registry_add_listener(app.registry, &app.registry_listener, &registry_events, &app);

    {
        char args[1024];
        snprintf(args, sizeof(args),
            "{ source.ip = \"%s\"  source.port = %d  sess.latency.msec = %d"
            "  audio.format = \"S16BE\"  audio.rate = 48000"
            "  audio.channels = 2  audio.position = \"[ FL FR ]\""
            "  stream.props = { node.name = \"rtp-source\""
            "    media.class = \"Audio/Source\""
            "    node.always-process = true  node.autoconnect = false } }",
            cfg.address, cfg.port, cfg.latency_ms);

        if (!pw_context_load_module(app.context, "libpipewire-module-rtp-source", args, NULL)) {
            fprintf(stderr, "[receiver] Failed to load rtp-source module: %m\n");
            ret = -ENOENT; goto out_registry;
        }
    }

    fprintf(stderr, "[receiver] Running. Press Ctrl-C to stop.\n");
    pw_main_loop_run(app.loop);
    fprintf(stderr, "[receiver] Shutting down.\n");

out_registry:
    destroy_links(&app);
    spa_hook_remove(&app.registry_listener);
    if (app.metadata) {
        spa_hook_remove(&app.metadata_listener);
        pw_proxy_destroy((struct pw_proxy *)app.metadata);
    }
    pw_proxy_destroy((struct pw_proxy *)app.registry);
out_core:
    spa_hook_remove(&app.core_listener);
    pw_core_disconnect(app.core);
out_ctx:
    pw_context_destroy(app.context);
out_loop:
    pw_main_loop_destroy(app.loop);
out_init:
    pw_deinit();
    return ret;
}
