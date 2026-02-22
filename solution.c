#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/*
 * Resolution - HackerRank Problem
 *
 * Given n frames with power values, each frame can be:
 *   - Unused (resolution unchanged)
 *   - Magnify (multiply resolution by power[i])
 *   - Reduce (divide resolution by power[i])
 *   - Both (resolution unchanged, but counts as different from unused)
 *
 * For each target, count configurations achieving that resolution (mod 10^9+7).
 *
 * Approach:
 *   Group frames by power value. For k frames with power v, the number of
 *   ways to achieve net multiplicative exponent j is C(2k, k+j).
 *   Track prime-factorization exponent vectors via DP with a hash map.
 */

#define MOD 1000000007LL
#define HT_SIZE 200003
#define MAX_PRIMES 20

static int g_np;

static long long mod_pow(long long base, long long exp, long long mod) {
    long long result = 1;
    base %= mod;
    while (exp > 0) {
        if (exp & 1) result = result * base % mod;
        base = base * base % mod;
        exp >>= 1;
    }
    return result;
}

static long long *g_fact = NULL, *g_ifact = NULL;
static int g_fact_sz = 0;

static void init_fact(int n) {
    if (g_fact_sz > n) return;
    n += 10;
    g_fact = (long long *)realloc(g_fact, (n + 1) * sizeof(long long));
    g_ifact = (long long *)realloc(g_ifact, (n + 1) * sizeof(long long));
    g_fact[0] = 1;
    for (int i = 1; i <= n; i++)
        g_fact[i] = g_fact[i - 1] * i % MOD;
    g_ifact[n] = mod_pow(g_fact[n], MOD - 2, MOD);
    for (int i = n - 1; i >= 0; i--)
        g_ifact[i] = g_ifact[i + 1] * (i + 1) % MOD;
    g_fact_sz = n + 1;
}

static long long comb(int n, int k) {
    if (k < 0 || k > n) return 0;
    return g_fact[n] % MOD * g_ifact[k] % MOD * g_ifact[n - k] % MOD;
}

typedef struct {
    int e[MAX_PRIMES];
} State;

typedef struct HEntry {
    State state;
    long long count;
    struct HEntry *next;
} HEntry;

typedef struct {
    HEntry *buckets[HT_SIZE];
} HashMap;

static unsigned int hash_state(const State *s) {
    unsigned int h = 0;
    for (int i = 0; i < g_np; i++)
        h = h * 100003u + (unsigned int)(s->e[i] + 100000);
    return h % HT_SIZE;
}

static int state_eq(const State *a, const State *b) {
    for (int i = 0; i < g_np; i++)
        if (a->e[i] != b->e[i]) return 0;
    return 1;
}

static HashMap *hm_new(void) {
    return (HashMap *)calloc(1, sizeof(HashMap));
}

static void hm_add(HashMap *m, const State *s, long long c) {
    unsigned int h = hash_state(s);
    for (HEntry *e = m->buckets[h]; e; e = e->next) {
        if (state_eq(&e->state, s)) {
            e->count = (e->count + c) % MOD;
            return;
        }
    }
    HEntry *e = (HEntry *)malloc(sizeof(HEntry));
    e->state = *s;
    e->count = c % MOD;
    e->next = m->buckets[h];
    m->buckets[h] = e;
}

static long long hm_get(HashMap *m, const State *s) {
    unsigned int h = hash_state(s);
    for (HEntry *e = m->buckets[h]; e; e = e->next)
        if (state_eq(&e->state, s)) return e->count;
    return 0;
}

static void hm_free(HashMap *m) {
    for (int i = 0; i < HT_SIZE; i++) {
        HEntry *e = m->buckets[i];
        while (e) {
            HEntry *nx = e->next;
            free(e);
            e = nx;
        }
    }
    free(m);
}

typedef struct {
    State *states;
    long long *counts;
    int size;
} EntryList;

static EntryList hm_entries(HashMap *m) {
    int cnt = 0;
    for (int i = 0; i < HT_SIZE; i++)
        for (HEntry *e = m->buckets[i]; e; e = e->next)
            cnt++;

    EntryList el;
    el.size = cnt;
    el.states = (State *)malloc(cnt * sizeof(State));
    el.counts = (long long *)malloc(cnt * sizeof(long long));

    int idx = 0;
    for (int i = 0; i < HT_SIZE; i++)
        for (HEntry *e = m->buckets[i]; e; e = e->next) {
            el.states[idx] = e->state;
            el.counts[idx] = e->count;
            idx++;
        }
    return el;
}

static int int_cmp(const void *a, const void *b) {
    return (*(int *)a > *(int *)b) - (*(int *)a < *(int *)b);
}

/*
 * Complete the 'calcNumberOfWays' function below.
 *
 * The function is expected to return an INTEGER_ARRAY.
 * The function accepts following parameters:
 *  1. INTEGER_ARRAY power
 *  2. LONG_INTEGER_ARRAY target
 */
int* calcNumberOfWays(int power_count, int* power, int target_count, long* target, int* result_count) {
    int primes[500], np = 0;

    for (int i = 0; i < power_count; i++) {
        int n = power[i];
        for (int p = 2; (long long)p * p <= n; p++) {
            if (n % p == 0) {
                int found = 0;
                for (int j = 0; j < np; j++)
                    if (primes[j] == p) { found = 1; break; }
                if (!found) primes[np++] = p;
                while (n % p == 0) n /= p;
            }
        }
        if (n > 1) {
            int found = 0;
            for (int j = 0; j < np; j++)
                if (primes[j] == n) { found = 1; break; }
            if (!found) primes[np++] = n;
        }
    }

    qsort(primes, np, sizeof(int), int_cmp);
    g_np = np;

    int *sp = (int *)malloc(power_count * sizeof(int));
    memcpy(sp, power, power_count * sizeof(int));
    qsort(sp, power_count, sizeof(int), int_cmp);

    init_fact(2 * power_count + 10);

    HashMap *dp = hm_new();
    State zero;
    memset(&zero, 0, sizeof(State));
    hm_add(dp, &zero, 1);

    int idx = 0;
    while (idx < power_count) {
        int v = sp[idx], k = 0;
        while (idx + k < power_count && sp[idx + k] == v) k++;
        idx += k;

        int ve[MAX_PRIMES];
        memset(ve, 0, sizeof(ve));
        int vv = v;
        for (int pi = 0; pi < np; pi++)
            while (vv % primes[pi] == 0) { ve[pi]++; vv /= primes[pi]; }

        int is_one = 1;
        for (int pi = 0; pi < np; pi++)
            if (ve[pi]) { is_one = 0; break; }

        EntryList el = hm_entries(dp);
        HashMap *ndp = hm_new();

        if (is_one) {
            long long mult = mod_pow(4, k, MOD);
            for (int i = 0; i < el.size; i++)
                hm_add(ndp, &el.states[i], el.counts[i] * mult % MOD);
        } else {
            for (int i = 0; i < el.size; i++) {
                for (int j = -k; j <= k; j++) {
                    long long co = comb(2 * k, k + j);
                    State ns = el.states[i];
                    for (int pi = 0; pi < np; pi++)
                        ns.e[pi] += j * ve[pi];
                    hm_add(ndp, &ns, el.counts[i] * co % MOD);
                }
            }
        }

        free(el.states);
        free(el.counts);
        hm_free(dp);
        dp = ndp;
    }

    free(sp);

    *result_count = target_count;
    int *result = (int *)malloc(target_count * sizeof(int));

    for (int i = 0; i < target_count; i++) {
        long long t = (long long)target[i];
        if (t <= 0) { result[i] = 0; continue; }

        State ts;
        memset(&ts, 0, sizeof(State));
        for (int pi = 0; pi < np; pi++)
            while (t % primes[pi] == 0) { ts.e[pi]++; t /= primes[pi]; }

        result[i] = (t != 1) ? 0 : (int)(hm_get(dp, &ts) % MOD);
    }

    hm_free(dp);
    return result;
}

/* ---- Test harness (not part of HackerRank submission) ---- */

int main(void) {
    {
        int power[] = {1, 2};
        long target[] = {1, 2, 4};
        int rc;
        int *res = calcNumberOfWays(2, power, 3, target, &rc);
        printf("Test 1: n=2, power=[1,2], targets=[1,2,4]\n");
        for (int i = 0; i < rc; i++)
            printf("  target=%ld -> %d\n", target[i], res[i]);
        free(res);
    }
    {
        int power[] = {2, 3};
        long target[] = {1, 2, 3, 6};
        int rc;
        int *res = calcNumberOfWays(2, power, 4, target, &rc);
        printf("Test 2: n=2, power=[2,3], targets=[1,2,3,6]\n");
        for (int i = 0; i < rc; i++)
            printf("  target=%ld -> %d\n", target[i], res[i]);
        free(res);
    }
    {
        int power[] = {2, 2, 2};
        long target[] = {1, 2, 4, 8};
        int rc;
        int *res = calcNumberOfWays(3, power, 4, target, &rc);
        printf("Test 3: n=3, power=[2,2,2], targets=[1,2,4,8]\n");
        for (int i = 0; i < rc; i++)
            printf("  target=%ld -> %d\n", target[i], res[i]);
        free(res);
    }
    return 0;
}
