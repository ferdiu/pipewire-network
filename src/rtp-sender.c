/* rtp-sender.c
 *
 * Creates a user-visible null-sink ("Network audio to <n>") and wires its
 * monitor ports to an RTP sender, so that whatever the user plays through the
 * sink is streamed over the network.
 *
 * Bug-fixes vs. v2:
 *  1. (sender) Only first channel was linked: try_create_links() used to fire
 *     as soon as ≥1 port was seen on each side, then set links_created=true.
 *     This meant the second channel's ports were ignored.
 *     Fix: wait until BOTH sides have exactly N_CHANNELS ports before linking.
 *
 * Usage:
 *   rtp-sender <n> <destination-ip> [destination-port]
 *
 * Example:
 *   rtp-sender living-room 192.168.1.42 9875
 *
 * Compile:
 *   gcc -Wall -O2 rtp-sender.c -o rtp-sender \
 *       $(pkg-config --cflags --libs libpipewire-0.3)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>

#include <pipewire/pipewire.h>
#include <pipewire/impl.h>

#define DEFAULT_PORT 9875

/* Number of audio channels (stereo) */
#define N_CHANNELS 2
/* Array capacity — same value, kept separate for clarity */
#define MAX_PORTS  N_CHANNELS

/* ─── port tracking ─────────────────────────────────────────────────────── */

struct port_entry {
    uint32_t global_id;   /* PipeWire global id of the Port object */
    uint32_t port_index;  /* port.id (channel index within the node) */
};

/* ─── application state ─────────────────────────────────────────────────── */

struct app {
    struct pw_main_loop  *loop;
    struct pw_context    *context;
    struct pw_core       *core;
    struct pw_registry   *registry;
    struct spa_hook       registry_listener;
    struct spa_hook       core_listener;

    /* names */
    const char *name;
    const char *dest_ip;
    int         dest_port;

    char null_sink_name[256];
    char rtp_sink_name[256];

    /* global-id of each node, filled when we see the Node global */
    uint32_t null_sink_node_id;
    uint32_t rtp_sink_node_id;

    /* monitor output ports of the null-sink (FL, FR ...) */
    struct port_entry monitor_ports[MAX_PORTS];
    int               n_monitor_ports;

    /* capture input ports of the rtp-sink stream (FL, FR ...) */
    struct port_entry capture_ports[MAX_PORTS];
    int               n_capture_ports;

    /* have we already created the links? */
    bool links_created;
};

/* ─── forward declarations ───────────────────────────────────────────────── */
static void try_create_links(struct app *app);

/* ─── signal handler ─────────────────────────────────────────────────────── */

static void on_signal(void *data, int signo)
{
    (void)signo;
    struct app *app = data;
    pw_main_loop_quit(app->loop);
}

/* ─── core error handler ─────────────────────────────────────────────────── */

static void on_core_error(void *data, uint32_t id, int seq,
                          int res, const char *message)
{
    struct app *app = data;
    fprintf(stderr, "core error: id=%u seq=%d res=%d (%s): %s\n",
            id, seq, res, strerror(-res), message);
    if (id == PW_ID_CORE)
        pw_main_loop_quit(app->loop);
}

static const struct pw_core_events core_events = {
    PW_VERSION_CORE_EVENTS,
    .error = on_core_error,
};

/* ─── registry listener ──────────────────────────────────────────────────── */

static void registry_event_global(void *data,
                                   uint32_t id,
                                   uint32_t permissions,
                                   const char *type,
                                   uint32_t version,
                                   const struct spa_dict *props)
{
    struct app *app = data;
    (void)permissions; (void)version;

    if (!props)
        return;

    /* ── Track our node ids ── */
    if (strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
        const char *name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
        if (!name)
            return;

        if (strcmp(name, app->null_sink_name) == 0) {
            app->null_sink_node_id = id;
            printf("[rtp-sender] Saw null-sink node id=%u\n", id);
        } else if (strcmp(name, app->rtp_sink_name) == 0) {
            app->rtp_sink_node_id = id;
            printf("[rtp-sender] Saw rtp-sink node id=%u\n", id);
        }
        return;
    }

    /* ── Collect ports we want to link ── */
    if (strcmp(type, PW_TYPE_INTERFACE_Port) == 0) {
        const char *node_id_str = spa_dict_lookup(props, "node.id");
        const char *direction   = spa_dict_lookup(props, PW_KEY_PORT_DIRECTION);
        const char *port_id_str = spa_dict_lookup(props, PW_KEY_PORT_ID);
        const char *is_monitor  = spa_dict_lookup(props, "port.monitor");

        if (!node_id_str || !direction || !port_id_str)
            return;

        uint32_t node_id    = (uint32_t)atoi(node_id_str);
        uint32_t port_index = (uint32_t)atoi(port_id_str);

        /* Monitor output port of the null-sink */
        if (node_id == app->null_sink_node_id &&
            strcmp(direction, "out") == 0 &&
            is_monitor && strcmp(is_monitor, "true") == 0)
        {
            if (app->n_monitor_ports < MAX_PORTS) {
                int i = app->n_monitor_ports++;
                app->monitor_ports[i].global_id  = id;
                app->monitor_ports[i].port_index = port_index;
                const char *nm = spa_dict_lookup(props, PW_KEY_PORT_NAME);
                printf("[rtp-sender] Monitor port: global_id=%u name=%s\n",
                       id, nm ? nm : "?");
            }
        }

        /* Capture input port of the rtp-sink stream */
        if (node_id == app->rtp_sink_node_id &&
            strcmp(direction, "in") == 0)
        {
            if (app->n_capture_ports < MAX_PORTS) {
                int i = app->n_capture_ports++;
                app->capture_ports[i].global_id  = id;
                app->capture_ports[i].port_index = port_index;
                const char *nm = spa_dict_lookup(props, PW_KEY_PORT_NAME);
                printf("[rtp-sender] Capture port:  global_id=%u name=%s\n",
                       id, nm ? nm : "?");
            }
        }

        try_create_links(app);
    }
}

static void registry_event_global_remove(void *data, uint32_t id)
{
    (void)data; (void)id;
}

static const struct pw_registry_events registry_events = {
    PW_VERSION_REGISTRY_EVENTS,
    .global        = registry_event_global,
    .global_remove = registry_event_global_remove,
};

/* ─── link creation ──────────────────────────────────────────────────────── */

static int cmp_port_entry(const void *a, const void *b)
{
    const struct port_entry *pa = a, *pb = b;
    return (int)pa->port_index - (int)pb->port_index;
}

static void try_create_links(struct app *app)
{
    if (app->links_created)
        return;

    /*
     * CRITICAL: wait until ALL channels have been seen on BOTH sides before
     * creating any links.  The registry delivers port globals asynchronously
     * one-by-one.  If we link as soon as we see the first port on each side
     * we set links_created=true and the remaining channels are permanently
     * ignored, resulting in only the first channel (FL) being connected.
     *
     * We know exactly how many ports to expect: N_CHANNELS monitor outputs
     * from the null-sink and N_CHANNELS capture inputs from the rtp-sink.
     */
    if (app->n_monitor_ports < N_CHANNELS || app->n_capture_ports < N_CHANNELS)
        return;

    /* Sort by port.id (channel index) to align FL↔FL, FR↔FR etc. */
    qsort(app->monitor_ports, app->n_monitor_ports,
          sizeof(app->monitor_ports[0]), cmp_port_entry);
    qsort(app->capture_ports, app->n_capture_ports,
          sizeof(app->capture_ports[0]), cmp_port_entry);

    int n = N_CHANNELS;

    for (int i = 0; i < n; i++) {
        uint32_t out_port = app->monitor_ports[i].global_id;
        uint32_t in_port  = app->capture_ports[i].global_id;

        struct pw_properties *lprops = pw_properties_new(NULL, NULL);
        pw_properties_setf(lprops, PW_KEY_LINK_OUTPUT_PORT, "%u", out_port);
        pw_properties_setf(lprops, PW_KEY_LINK_INPUT_PORT,  "%u", in_port);
        /*
         * passive link: keeps both nodes awake only when user audio is
         * flowing (i.e. when something is connected to the null-sink input).
         * Without this the rtp-sink would run even when nothing plays.
         */
        pw_properties_set(lprops, "link.passive", "true");

        struct pw_proxy *link =
            pw_core_create_object(app->core,
                                  "link-factory",
                                  PW_TYPE_INTERFACE_Link,
                                  PW_VERSION_LINK,
                                  &lprops->dict, 0);
        pw_properties_free(lprops);

        if (link)
            printf("[rtp-sender] Created link: port %u -> port %u\n",
                   out_port, in_port);
        else
            fprintf(stderr,
                    "[rtp-sender] Failed to create link %d: %m\n", i);
    }

    app->links_created = true;
    printf("[rtp-sender] All links created. Streaming to %s:%d\n",
           app->dest_ip, app->dest_port);
}

/* ─── main ───────────────────────────────────────────────────────────────── */

int main(int argc, char *argv[])
{
    struct app app = { 0 };
    int ret = 0;

    app.null_sink_node_id = SPA_ID_INVALID;
    app.rtp_sink_node_id  = SPA_ID_INVALID;

    /* ── argument parsing ── */
    if (argc < 3) {
        fprintf(stderr,
                "Usage: %s <n> <destination-ip> [destination-port]\n"
                "\n"
                "  name             friendly name (e.g. \"living-room\")\n"
                "  destination-ip   IP address to stream RTP to\n"
                "  destination-port UDP port (default %d)\n",
                argv[0], DEFAULT_PORT);
        return 1;
    }

    app.name      = argv[1];
    app.dest_ip   = argv[2];
    app.dest_port = (argc >= 4) ? atoi(argv[3]) : DEFAULT_PORT;

    snprintf(app.null_sink_name, sizeof(app.null_sink_name),
             "rtp-sink-main-%s", app.name);
    snprintf(app.rtp_sink_name,  sizeof(app.rtp_sink_name),
             "rtp-sink-%s", app.name);

    /* ── PipeWire initialisation ── */
    pw_init(&argc, &argv);

    app.loop = pw_main_loop_new(NULL);
    if (!app.loop) {
        fprintf(stderr, "Failed to create main loop: %m\n");
        ret = -errno; goto cleanup_init;
    }

    {
        struct pw_loop *l = pw_main_loop_get_loop(app.loop);
        pw_loop_add_signal(l, SIGINT,  on_signal, &app);
        pw_loop_add_signal(l, SIGTERM, on_signal, &app);
    }

    app.context = pw_context_new(pw_main_loop_get_loop(app.loop), NULL, 0);
    if (!app.context) {
        fprintf(stderr, "Failed to create context: %m\n");
        ret = -errno; goto cleanup_loop;
    }

    /* Load link-factory so pw_core_create_object("link-factory",...) works */
    if (!pw_context_load_module(app.context,
                                "libpipewire-module-link-factory", NULL, NULL)) {
        fprintf(stderr, "Failed to load libpipewire-module-link-factory: %m\n");
        ret = -errno; goto cleanup_ctx;
    }

    app.core = pw_context_connect(app.context, NULL, 0);
    if (!app.core) {
        fprintf(stderr, "Failed to connect to PipeWire: %m\n");
        ret = -errno; goto cleanup_ctx;
    }

    pw_core_add_listener(app.core, &app.core_listener, &core_events, &app);

    /* ── Registry ── */
    app.registry = pw_core_get_registry(app.core, PW_VERSION_REGISTRY, 0);
    if (!app.registry) {
        fprintf(stderr, "Failed to get registry: %m\n");
        ret = -errno; goto cleanup_core;
    }
    pw_registry_add_listener(app.registry, &app.registry_listener,
                             &registry_events, &app);

    /* ── Step 1: create the null-sink ──────────────────────────────────────
     *
     * FIX #1: NO object.linger → node dies when this client disconnects.
     */
    {
        char description[256];
        snprintf(description, sizeof(description),
                 "Network audio to %s", app.name);

        struct pw_properties *props = pw_properties_new(
            "factory.name",          "support.null-audio-sink",
            PW_KEY_NODE_NAME,        app.null_sink_name,
            PW_KEY_NODE_DESCRIPTION, description,
            "media.class",           "Audio/Sink",
            "audio.position",        "[ FL FR ]",
            "device.description",    description,
            "device.class",          "sound",
            "device.icon-name",      "audio-card",
            "node.virtual",          "false",
            NULL);

        struct pw_proxy *proxy =
            pw_core_create_object(app.core,
                                  "adapter",
                                  PW_TYPE_INTERFACE_Node,
                                  PW_VERSION_NODE,
                                  &props->dict, 0);
        pw_properties_free(props);

        if (!proxy) {
            fprintf(stderr, "Failed to create null-sink node: %m\n");
            ret = -errno; goto cleanup_registry;
        }

        printf("[rtp-sender] Created null-sink '%s'\n", app.null_sink_name);
        printf("[rtp-sender] Description: Network audio to %s\n", app.name);
    }

    /* ── Step 2: load rtp-sink module ──────────────────────────────────────
     *
     * FIX #2: node.autoconnect = false → no auto-connect to the microphone.
     * FIX #3: NO target.object — explicit links are created from the registry.
     */
    {
        char args[2048];
        snprintf(args, sizeof(args),
            "{"
            "  source.ip        = \"0.0.0.0\""
            "  destination.ip   = \"%s\""
            "  destination.port = %d"
            "  sess.latency.msec = 5"
            "  audio.format     = \"S16BE\""
            "  audio.rate       = 48000"
            "  audio.channels   = 2"
            "  audio.position   = \"[ FL FR ]\""
            "  stream.props = {"
            "    node.name         = \"%s\""
            "    node.autoconnect  = false"
            "    node.passive      = true"
            "  }"
            "}",
            app.dest_ip,
            app.dest_port,
            app.rtp_sink_name);

        struct pw_impl_module *mod =
            pw_context_load_module(app.context,
                                   "libpipewire-module-rtp-sink",
                                   args, NULL);
        if (!mod) {
            fprintf(stderr,
                    "Failed to load libpipewire-module-rtp-sink: %m\n"
                    "Make sure PipeWire >= 0.3.60 is installed.\n");
            ret = -errno; goto cleanup_registry;
        }

        printf("[rtp-sender] Loaded rtp-sink '%s'\n", app.rtp_sink_name);
        printf("[rtp-sender] Waiting for ports to link...\n");
    }

    printf("[rtp-sender] Running. Press Ctrl-C to stop.\n");

    pw_main_loop_run(app.loop);

    printf("[rtp-sender] Shutting down.\n");

cleanup_registry:
    spa_hook_remove(&app.registry_listener);
    pw_proxy_destroy((struct pw_proxy *)app.registry);
cleanup_core:
    spa_hook_remove(&app.core_listener);
    pw_core_disconnect(app.core);
cleanup_ctx:
    pw_context_destroy(app.context);
cleanup_loop:
    pw_main_loop_destroy(app.loop);
cleanup_init:
    pw_deinit();
    return ret;
}
