/* pipewire-network-sender.c
 *
 * Reads a named configuration from ~/.config/pipewire-network/sender.json
 * (fallback: /etc/pipewire-network/sender.json) and runs one rtp-sender
 * child process per stream entry.  Children are restarted automatically
 * according to retry_interval / max_retries.
 *
 * Usage: pipewire-network-sender <config-name>
 *   e.g. pipewire-network-sender default
 *        pipewire-network-sender living-room
 *
 * JSON config format:
 *   {
 *     "living-room": {
 *       "streams": [ { "address": "192.168.1.3", "port": 9875 } ],
 *       "auto_connect":    true,
 *       "retry_interval":  10,
 *       "max_retries":     3        <- -1 = unlimited
 *     }
 *   }
 *
 * Compile: see Makefile
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>

#include <json-c/json.h>

#define MAX_STREAMS   32
#define SENDER_BIN    "pipewire-network-rtp-sender"

/* ─── stream descriptor ──────────────────────────────────────────────────── */
struct stream {
    char address[64];
    int  port;

    /* runtime state */
    pid_t pid;
    int   retries;
    time_t last_start;
};

/* ─── configuration for one named config ─────────────────────────────────── */
struct config {
    char config_name[128];
    struct stream streams[MAX_STREAMS];
    int  n_streams;
    bool auto_connect;
    int  retry_interval;  /* seconds between restarts */
    int  max_retries;     /* -1 = unlimited */
};

static void config_defaults(struct config *c, const char *name)
{
    memset(c, 0, sizeof(*c));
    strncpy(c->config_name, name, sizeof(c->config_name) - 1);
    c->auto_connect   = true;
    c->retry_interval = 10;
    c->max_retries    = -1;
}

static int config_load(struct config *c, const char *path, const char *name)
{
    struct json_object *root = json_object_from_file(path);
    if (!root) return -1;

    struct json_object *cfg_obj;
    if (!json_object_object_get_ex(root, name, &cfg_obj)) {
        fprintf(stderr, "[sender] Config name '%s' not found in %s\n", name, path);
        json_object_put(root);
        return -1;
    }

    struct json_object *v;
    if (json_object_object_get_ex(cfg_obj, "auto_connect", &v))
        c->auto_connect = json_object_get_boolean(v);
    if (json_object_object_get_ex(cfg_obj, "retry_interval", &v))
        c->retry_interval = json_object_get_int(v);
    if (json_object_object_get_ex(cfg_obj, "max_retries", &v))
        c->max_retries = json_object_get_int(v);

    struct json_object *streams_arr;
    if (json_object_object_get_ex(cfg_obj, "streams", &streams_arr)) {
        int n = json_object_array_length(streams_arr);
        for (int i = 0; i < n && i < MAX_STREAMS; i++) {
            struct json_object *s = json_object_array_get_idx(streams_arr, i);
            struct stream *st = &c->streams[c->n_streams++];
            st->pid = -1;
            strncpy(st->address, "127.0.0.1", sizeof(st->address) - 1);
            st->port = 9875;

            struct json_object *sv;
            if (json_object_object_get_ex(s, "address", &sv))
                strncpy(st->address, json_object_get_string(sv), sizeof(st->address) - 1);
            if (json_object_object_get_ex(s, "port", &sv))
                st->port = json_object_get_int(sv);
        }
    }

    json_object_put(root);
    return 0;
}

static int config_load_best(struct config *c, const char *name)
{
    config_defaults(c, name);
    const char *home = getenv("HOME");
    if (home) {
        char path[512];
        snprintf(path, sizeof(path), "%s/.config/pipewire-network/sender.json", home);
        if (config_load(c, path, name) == 0) {
            fprintf(stderr, "[sender] Config '%s' loaded from %s\n", name, path);
            return 0;
        }
    }
    if (config_load(c, "/etc/pipewire-network/sender.json", name) == 0) {
        fprintf(stderr, "[sender] Config '%s' loaded from /etc/pipewire-network/sender.json\n", name);
        return 0;
    }
    fprintf(stderr, "[sender] Config '%s' not found in any config file\n", name);
    return -1;
}

/* ─── global quit flag ───────────────────────────────────────────────────── */
static volatile sig_atomic_t g_quit = 0;
static void on_signal(int sig) { (void)sig; g_quit = 1; }

/* ─── spawn a single rtp-sender child ───────────────────────────────────── */
/*
 * The child runs:  pipewire-network-rtp-sender <config-name>-<index> <address> <port>
 * The sink name is derived from the config name + stream index so each stream
 * gets a unique, identifiable null-sink in the audio mixer.
 */
static void spawn_stream(struct config *cfg, int idx)
{
    struct stream *s = &cfg->streams[idx];

    char sink_name[128];
    /* Sanitise config_name: replace spaces/special chars with '-' */
    char safe_name[128];
    strncpy(safe_name, cfg->config_name, sizeof(safe_name) - 1);
    for (char *p = safe_name; *p; p++)
        if (*p == ' ' || *p == '/' || *p == '\\') *p = '-';

    snprintf(sink_name, sizeof(sink_name), "%s-%d", safe_name, idx);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", s->port);

    pid_t pid = fork();
    if (pid < 0) {
        fprintf(stderr, "[sender] fork failed for stream %d: %m\n", idx);
        return;
    }
    if (pid == 0) {
        /* child */
        execlp(SENDER_BIN, SENDER_BIN, sink_name, s->address, port_str, NULL);
        /* execlp failed — try path relative to our own binary */
        char self[512]; ssize_t n = readlink("/proc/self/exe", self, sizeof(self)-1);
        if (n > 0) {
            self[n] = '\0';
            char *slash = strrchr(self, '/');
            if (slash) { slash[1] = '\0'; strncat(self, SENDER_BIN, sizeof(self)-strlen(self)-1); }
            execl(self, SENDER_BIN, sink_name, s->address, port_str, NULL);
        }
        fprintf(stderr, "[sender] exec %s failed: %m\n", SENDER_BIN);
        _exit(1);
    }

    s->pid        = pid;
    s->last_start = time(NULL);
    fprintf(stderr, "[sender] Stream %d (%s:%d) started as pid %d\n",
            idx, s->address, s->port, pid);
}

/* ─── main loop ──────────────────────────────────────────────────────────── */
int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <config-name>\n", argv[0]);
        return 1;
    }

    struct config cfg;
    if (config_load_best(&cfg, argv[1]) < 0) return 1;

    if (cfg.n_streams == 0) {
        fprintf(stderr, "[sender] No streams configured for '%s'\n", argv[1]);
        return 1;
    }

    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGCHLD, SIG_DFL);   /* default: allow waitpid to reap */

    fprintf(stderr, "[sender] Starting %d stream(s) for config '%s'\n",
            cfg.n_streams, cfg.config_name);

    /* Initial spawn */
    for (int i = 0; i < cfg.n_streams; i++) {
        cfg.streams[i].pid     = -1;
        cfg.streams[i].retries = 0;
        spawn_stream(&cfg, i);
    }

    /* Supervision loop */
    while (!g_quit) {
        /* Reap any finished children */
        int status;
        pid_t died;
        while ((died = waitpid(-1, &status, WNOHANG)) > 0) {
            for (int i = 0; i < cfg.n_streams; i++) {
                if (cfg.streams[i].pid != died) continue;

                int code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
                fprintf(stderr, "[sender] Stream %d (pid %d) exited (code=%d)\n",
                        i, died, code);
                cfg.streams[i].pid = -1;

                if (!cfg.auto_connect) break;

                /* Check retry limit */
                if (cfg.max_retries >= 0 && cfg.streams[i].retries >= cfg.max_retries) {
                    fprintf(stderr, "[sender] Stream %d exceeded max_retries (%d), giving up\n",
                            i, cfg.max_retries);
                    break;
                }

                /* Honour retry_interval */
                time_t now = time(NULL);
                time_t elapsed = now - cfg.streams[i].last_start;
                if (elapsed < cfg.retry_interval) {
                    long wait = cfg.retry_interval - elapsed;
                    fprintf(stderr, "[sender] Stream %d will restart in %lds\n", i, wait);
                    /* We'll catch it next iteration */
                } else {
                    cfg.streams[i].retries++;
                    spawn_stream(&cfg, i);
                }
                break;
            }
        }

        /* Delayed restarts: check streams with pid==-1 that are past their interval */
        if (!g_quit) {
            time_t now = time(NULL);
            for (int i = 0; i < cfg.n_streams; i++) {
                struct stream *s = &cfg.streams[i];
                if (s->pid != -1) continue;
                if (!cfg.auto_connect) continue;
                if (cfg.max_retries >= 0 && s->retries >= cfg.max_retries) continue;
                if ((now - s->last_start) >= cfg.retry_interval) {
                    s->retries++;
                    spawn_stream(&cfg, i);
                }
            }
            sleep(1);
        }
    }

    /* Shutdown: SIGTERM all children */
    fprintf(stderr, "[sender] Shutting down, stopping all streams...\n");
    for (int i = 0; i < cfg.n_streams; i++) {
        if (cfg.streams[i].pid > 0) {
            kill(cfg.streams[i].pid, SIGTERM);
        }
    }
    /* Wait up to 5s for children */
    for (int i = 0; i < cfg.n_streams; i++) {
        if (cfg.streams[i].pid > 0) {
            int status;
            waitpid(cfg.streams[i].pid, &status, 0);
        }
    }
    fprintf(stderr, "[sender] Done.\n");
    return 0;
}
