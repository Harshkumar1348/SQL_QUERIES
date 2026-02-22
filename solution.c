#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MOD 1000000007

typedef struct {
    int len;
    int cap;
    int *idx;
    int *exp;
} FrameFactors;

typedef struct {
    int count;
    int cap;
    long long *values;
} PrimeList;

typedef struct {
    int dims;
    size_t cap;
    size_t size;
    unsigned char *used;
    int *keys;
    int *vals;
} VecMap;

static int mod_pow(int base, int exp) {
    long long result = 1;
    long long b = base;
    while (exp > 0) {
        if (exp & 1) {
            result = (result * b) % MOD;
        }
        b = (b * b) % MOD;
        exp >>= 1;
    }
    return (int)result;
}

static int prime_list_find(const PrimeList *pl, long long p) {
    for (int i = 0; i < pl->count; ++i) {
        if (pl->values[i] == p) {
            return i;
        }
    }
    return -1;
}

static int prime_list_add(PrimeList *pl, long long p) {
    int idx = prime_list_find(pl, p);
    if (idx >= 0) {
        return idx;
    }

    if (pl->count == pl->cap) {
        int next_cap = pl->cap == 0 ? 8 : pl->cap * 2;
        long long *next_values =
            (long long *)realloc(pl->values, (size_t)next_cap * sizeof(long long));
        if (next_values == NULL) {
            return -1;
        }
        pl->values = next_values;
        pl->cap = next_cap;
    }

    pl->values[pl->count] = p;
    pl->count += 1;
    return pl->count - 1;
}

static int frame_push(FrameFactors *f, int idx, int exp) {
    if (f->len == f->cap) {
        int next_cap = f->cap == 0 ? 4 : f->cap * 2;
        int *next_idx = (int *)realloc(f->idx, (size_t)next_cap * sizeof(int));
        int *next_exp = (int *)realloc(f->exp, (size_t)next_cap * sizeof(int));
        if (next_idx == NULL || next_exp == NULL) {
            free(next_idx);
            free(next_exp);
            return 0;
        }
        f->idx = next_idx;
        f->exp = next_exp;
        f->cap = next_cap;
    }
    f->idx[f->len] = idx;
    f->exp[f->len] = exp;
    f->len += 1;
    return 1;
}

static int factorize_power_into_frame(int x, PrimeList *pl, FrameFactors *frame) {
    frame->len = 0;
    frame->cap = 0;
    frame->idx = NULL;
    frame->exp = NULL;

    if (x < 0) {
        x = -x;
    }
    if (x <= 1) {
        return 1;
    }

    long long v = (long long)x;
    int cnt = 0;

    while ((v % 2LL) == 0) {
        v /= 2LL;
        cnt++;
    }
    if (cnt > 0) {
        int pidx = prime_list_add(pl, 2);
        if (pidx < 0 || !frame_push(frame, pidx, cnt)) {
            return 0;
        }
    }

    for (long long p = 3; p * p <= v; p += 2) {
        if (v % p != 0) {
            continue;
        }
        cnt = 0;
        while (v % p == 0) {
            v /= p;
            cnt++;
        }
        int pidx = prime_list_add(pl, p);
        if (pidx < 0 || !frame_push(frame, pidx, cnt)) {
            return 0;
        }
    }

    if (v > 1) {
        int pidx = prime_list_add(pl, v);
        if (pidx < 0 || !frame_push(frame, pidx, 1)) {
            return 0;
        }
    }

    return 1;
}

static void frame_free(FrameFactors *f) {
    free(f->idx);
    free(f->exp);
    f->idx = NULL;
    f->exp = NULL;
    f->len = 0;
    f->cap = 0;
}

static size_t ceil_pow2(size_t x) {
    size_t p = 1;
    while (p < x) {
        p <<= 1;
    }
    return p < 8 ? 8 : p;
}

static uint64_t mix64(uint64_t z) {
    z ^= z >> 33;
    z *= 0xff51afd7ed558ccdULL;
    z ^= z >> 33;
    z *= 0xc4ceb9fe1a85ec53ULL;
    z ^= z >> 33;
    return z;
}

static uint64_t hash_vec(const int *vec, int dims) {
    uint64_t h = 0x9e3779b97f4a7c15ULL;
    for (int i = 0; i < dims; ++i) {
        uint64_t x = (uint64_t)(uint32_t)vec[i];
        h ^= mix64(x + 0x9e3779b97f4a7c15ULL + ((uint64_t)i << 1));
        h = (h << 27) | (h >> (64 - 27));
        h = h * 5ULL + 0x52dce729ULL;
    }
    return h;
}

static int map_init(VecMap *m, int dims, size_t initial_capacity) {
    m->dims = dims;
    m->cap = ceil_pow2(initial_capacity);
    m->size = 0;
    m->used = (unsigned char *)calloc(m->cap, sizeof(unsigned char));
    m->vals = (int *)calloc(m->cap, sizeof(int));
    if (m->used == NULL || m->vals == NULL) {
        free(m->used);
        free(m->vals);
        m->used = NULL;
        m->vals = NULL;
        return 0;
    }
    if (dims > 0) {
        m->keys = (int *)calloc(m->cap * (size_t)dims, sizeof(int));
        if (m->keys == NULL) {
            free(m->used);
            free(m->vals);
            m->used = NULL;
            m->vals = NULL;
            return 0;
        }
    } else {
        m->keys = NULL;
    }
    return 1;
}

static void map_free(VecMap *m) {
    free(m->used);
    free(m->keys);
    free(m->vals);
    m->used = NULL;
    m->keys = NULL;
    m->vals = NULL;
    m->cap = 0;
    m->size = 0;
}

static int map_key_equal(const VecMap *m, size_t slot, const int *vec) {
    if (m->dims == 0) {
        return 1;
    }
    const int *slot_key = m->keys + slot * (size_t)m->dims;
    return memcmp(slot_key, vec, (size_t)m->dims * sizeof(int)) == 0;
}

static void map_set_key(VecMap *m, size_t slot, const int *vec) {
    if (m->dims > 0) {
        int *slot_key = m->keys + slot * (size_t)m->dims;
        memcpy(slot_key, vec, (size_t)m->dims * sizeof(int));
    }
}

static int map_add_no_resize(VecMap *m, const int *vec, int delta) {
    size_t mask = m->cap - 1;
    size_t pos = (size_t)(hash_vec(vec, m->dims) & mask);
    while (m->used[pos]) {
        if (map_key_equal(m, pos, vec)) {
            int next = m->vals[pos] + delta;
            if (next >= MOD) {
                next -= MOD;
            }
            m->vals[pos] = next;
            return 1;
        }
        pos = (pos + 1) & mask;
    }

    m->used[pos] = 1;
    map_set_key(m, pos, vec);
    m->vals[pos] = delta;
    m->size += 1;
    return 1;
}

static int map_rehash(VecMap *m, size_t new_cap) {
    VecMap fresh;
    if (!map_init(&fresh, m->dims, new_cap)) {
        return 0;
    }

    for (size_t i = 0; i < m->cap; ++i) {
        if (!m->used[i]) {
            continue;
        }
        const int *key = m->dims > 0 ? (m->keys + i * (size_t)m->dims) : NULL;
        if (!map_add_no_resize(&fresh, key, m->vals[i])) {
            map_free(&fresh);
            return 0;
        }
    }

    map_free(m);
    *m = fresh;
    return 1;
}

static int map_add(VecMap *m, const int *vec, long long delta_raw) {
    int delta = (int)(delta_raw % MOD);
    if (delta < 0) {
        delta += MOD;
    }

    if ((m->size + 1) * 10 > m->cap * 7) {
        if (!map_rehash(m, m->cap * 2)) {
            return 0;
        }
    }
    return map_add_no_resize(m, vec, delta);
}

static int map_get(const VecMap *m, const int *vec) {
    if (m->cap == 0) {
        return 0;
    }
    size_t mask = m->cap - 1;
    size_t pos = (size_t)(hash_vec(vec, m->dims) & mask);
    while (m->used[pos]) {
        if (map_key_equal(m, pos, vec)) {
            return m->vals[pos];
        }
        pos = (pos + 1) & mask;
    }
    return 0;
}

/*
 * Complete the 'calcNumberOfWays' function below.
 *
 * The function is expected to return an INTEGER_ARRAY.
 * The function accepts following parameters:
 *  1. INTEGER_ARRAY power
 *  2. LONG_INTEGER_ARRAY target
 */
int *calcNumberOfWays(int power_count, int *power, int target_count, long *target,
                      int *result_count) {
    *result_count = target_count;
    int *result = (int *)calloc((size_t)target_count, sizeof(int));
    if (result == NULL) {
        return NULL;
    }

    if (power_count == 0) {
        for (int i = 0; i < target_count; ++i) {
            result[i] = (target[i] == 1L) ? 1 : 0;
        }
        return result;
    }

    PrimeList plist;
    plist.count = 0;
    plist.cap = 0;
    plist.values = NULL;

    FrameFactors *frames =
        (FrameFactors *)calloc((size_t)power_count, sizeof(FrameFactors));
    if (frames == NULL) {
        free(result);
        return NULL;
    }

    for (int i = 0; i < power_count; ++i) {
        if (!factorize_power_into_frame(power[i], &plist, &frames[i])) {
            for (int j = 0; j <= i; ++j) {
                frame_free(&frames[j]);
            }
            free(frames);
            free(plist.values);
            free(result);
            return NULL;
        }
    }

    const int dims = plist.count;

    if (dims == 0) {
        int all_one_ways = mod_pow(4, power_count);
        for (int i = 0; i < target_count; ++i) {
            result[i] = (target[i] == 1L) ? all_one_ways : 0;
        }

        for (int i = 0; i < power_count; ++i) {
            frame_free(&frames[i]);
        }
        free(frames);
        free(plist.values);
        return result;
    }

    VecMap cur;
    if (!map_init(&cur, dims, 1024)) {
        for (int i = 0; i < power_count; ++i) {
            frame_free(&frames[i]);
        }
        free(frames);
        free(plist.values);
        free(result);
        return NULL;
    }

    int *zero = (int *)calloc((size_t)dims, sizeof(int));
    int *tmp = (int *)calloc((size_t)dims, sizeof(int));
    int *target_vec = (int *)calloc((size_t)dims, sizeof(int));
    if (zero == NULL || tmp == NULL || target_vec == NULL) {
        free(zero);
        free(tmp);
        free(target_vec);
        map_free(&cur);
        for (int i = 0; i < power_count; ++i) {
            frame_free(&frames[i]);
        }
        free(frames);
        free(plist.values);
        free(result);
        return NULL;
    }

    if (!map_add(&cur, zero, 1)) {
        free(zero);
        free(tmp);
        free(target_vec);
        map_free(&cur);
        for (int i = 0; i < power_count; ++i) {
            frame_free(&frames[i]);
        }
        free(frames);
        free(plist.values);
        free(result);
        return NULL;
    }

    for (int i = 0; i < power_count; ++i) {
        VecMap nxt;
        size_t expected = cur.size * 4 + 8;
        if (!map_init(&nxt, dims, expected)) {
            free(zero);
            free(tmp);
            free(target_vec);
            map_free(&cur);
            for (int j = 0; j < power_count; ++j) {
                frame_free(&frames[j]);
            }
            free(frames);
            free(plist.values);
            free(result);
            return NULL;
        }

        for (size_t slot = 0; slot < cur.cap; ++slot) {
            if (!cur.used[slot]) {
                continue;
            }

            const int *base = cur.keys + slot * (size_t)dims;
            int ways = cur.vals[slot];

            if (!map_add(&nxt, base, (2LL * ways) % MOD)) {
                map_free(&nxt);
                free(zero);
                free(tmp);
                free(target_vec);
                map_free(&cur);
                for (int j = 0; j < power_count; ++j) {
                    frame_free(&frames[j]);
                }
                free(frames);
                free(plist.values);
                free(result);
                return NULL;
            }

            memcpy(tmp, base, (size_t)dims * sizeof(int));
            for (int k = 0; k < frames[i].len; ++k) {
                tmp[frames[i].idx[k]] += frames[i].exp[k];
            }
            if (!map_add(&nxt, tmp, ways)) {
                map_free(&nxt);
                free(zero);
                free(tmp);
                free(target_vec);
                map_free(&cur);
                for (int j = 0; j < power_count; ++j) {
                    frame_free(&frames[j]);
                }
                free(frames);
                free(plist.values);
                free(result);
                return NULL;
            }

            memcpy(tmp, base, (size_t)dims * sizeof(int));
            for (int k = 0; k < frames[i].len; ++k) {
                tmp[frames[i].idx[k]] -= frames[i].exp[k];
            }
            if (!map_add(&nxt, tmp, ways)) {
                map_free(&nxt);
                free(zero);
                free(tmp);
                free(target_vec);
                map_free(&cur);
                for (int j = 0; j < power_count; ++j) {
                    frame_free(&frames[j]);
                }
                free(frames);
                free(plist.values);
                free(result);
                return NULL;
            }
        }

        map_free(&cur);
        cur = nxt;
    }

    for (int qi = 0; qi < target_count; ++qi) {
        memset(target_vec, 0, (size_t)dims * sizeof(int));

        long long v = (long long)target[qi];
        if (v <= 0) {
            result[qi] = 0;
            continue;
        }

        for (int pi = 0; pi < plist.count; ++pi) {
            long long p = plist.values[pi];
            while (v % p == 0) {
                target_vec[pi] += 1;
                v /= p;
            }
        }

        if (v != 1) {
            result[qi] = 0;
            continue;
        }

        result[qi] = map_get(&cur, target_vec);
    }

    free(zero);
    free(tmp);
    free(target_vec);
    map_free(&cur);

    for (int i = 0; i < power_count; ++i) {
        frame_free(&frames[i]);
    }
    free(frames);
    free(plist.values);
    return result;
}

