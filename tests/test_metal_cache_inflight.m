/* Model-free regression using the runtime's actual private cache routines.
 * Entries deliberately have no weight buffers: the bug is victim selection
 * and ownership bookkeeping, independent of GPU arithmetic or model size. */
#ifndef DS4_METAL_SOURCE
#define DS4_METAL_SOURCE "../ds4_metal.m"
#endif
#include DS4_METAL_SOURCE
#include <assert.h>
#include <signal.h>
bool ds4_log_is_tty(FILE *fp) { (void)fp; return false; }

static void seed(uint32_t expert, uint64_t inflight) {
    ds4_gpu_stream_expert_cache_entry *e = &g_stream_expert_cache[2][expert];
    e->valid = 1;
    e->inflight_seq = inflight;
    e->last_used = expert;
    g_stream_expert_cache_route_hotness[2][expert] = expert;
    g_stream_expert_cache_entry_count++;
    g_stream_expert_cache_layer_count[2]++;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    alarm(2); /* Bound any future eviction loop regression. */
    g_ssd_streaming_mode = 1;
    g_stream_expert_cache_budget_override = 1;
    g_stream_expert_cache_done_seq = 0;
    if (!strcmp(argv[1], "prune")) {
        seed(0, 1); seed(1, 0); seed(2, 0);
        ds4_gpu_stream_expert_cache_prune_global(UINT32_MAX, NULL, 0);
        assert(g_stream_expert_cache_entry_count == 1);
        assert(g_stream_expert_cache[2][0].valid);
        assert(!g_stream_expert_cache[2][1].valid);
        assert(!g_stream_expert_cache[2][2].valid);
    } else if (!strcmp(argv[1], "all-inflight")) {
        seed(0, 1); seed(1, 1);
        ds4_gpu_stream_expert_cache_prune_global(UINT32_MAX, NULL, 0);
        assert(g_stream_expert_cache_entry_count == 2);
    } else if (!strcmp(argv[1], "clear")) {
        seed(0, 1); seed(1, 0);
        ds4_gpu_stream_expert_cache_clear_layer(2);
        assert(g_stream_expert_cache_entry_count == 1);
        assert(g_stream_expert_cache_layer_count[2] == 1);
        assert(g_stream_expert_cache[2][0].valid);
        g_stream_expert_cache_done_seq = 1;
        ds4_gpu_stream_expert_cache_clear_layer(2);
        assert(g_stream_expert_cache_entry_count == 0);
        assert(g_stream_expert_cache_layer_count[2] == 0);
    } else if (!strcmp(argv[1], "completed")) {
        seed(0, 1); seed(1, 1);
        g_stream_expert_cache_done_seq = 1;
        ds4_gpu_stream_expert_cache_prune_global(UINT32_MAX, NULL, 0);
        assert(g_stream_expert_cache_entry_count == 1);
        assert(!g_stream_expert_cache[2][0].valid);
        assert(g_stream_expert_cache[2][1].valid);
    } else if (!strcmp(argv[1], "protected")) {
        seed(0, 1); seed(1, 0);
        const int32_t protected_id = 1;
        ds4_gpu_stream_expert_cache_prune_global(2, &protected_id, 1);
        assert(g_stream_expert_cache_entry_count == 2);
    } else return 2;
    alarm(0);
    printf("cache %s: PASS\n", argv[1]);
    return 0;
}
