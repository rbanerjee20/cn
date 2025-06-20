#ifndef CN_GEN_DSL_H
#define CN_GEN_DSL_H

#include <assert.h>
#include <stdlib.h>

#include <cn-testing/failure.h>

#define CN_GEN_CHECK_TIMEOUT()                                                           \
  if (cn_gen_get_input_timeout() != 0 &&                                                 \
      cn_gen_get_milliseconds() - cn_gen_get_input_timer() >                             \
          cn_gen_get_input_timeout()) {                                                  \
    cn_gen_failure_reset();                                                              \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ASSERT);                            \
    goto cn_label_bennet_backtrack;                                                      \
  }

#define CN_GEN_INIT()                                                                    \
  size_t cn_gen_rec_size = cn_gen_get_size();                                            \
  CN_GEN_INIT_SIZED();

#define CN_GEN_INIT_SIZED()                                                              \
  if (0) {                                                                               \
  cn_label_bennet_backtrack:                                                             \
    cn_gen_decrement_depth();                                                            \
    return NULL;                                                                         \
  }                                                                                      \
  CN_GEN_CHECK_TIMEOUT();                                                                \
  cn_gen_increment_depth();                                                              \
  if (cn_gen_rec_size <= 0 || cn_gen_depth() == cn_gen_max_depth()) {                    \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_DEPTH);                             \
    goto cn_label_bennet_backtrack;                                                      \
  }

#define CN_GEN_UNIFORM(ty)                                                               \
  ({                                                                                     \
    ty* result;                                                                          \
    if (cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_ALLOC) {                   \
      result = cast_cn_pointer_to_##ty(CN_GEN_ALLOC(convert_to_cn_bits_u64(0)));         \
    } else {                                                                             \
      result = cn_gen_uniform_##ty(0);                                                   \
    }                                                                                    \
    result;                                                                              \
  })

#define CN_GEN_ALLOC(sz)                                                                 \
  ({                                                                                     \
    cn_pointer* ptr;                                                                     \
    if (sz != 0) {                                                                       \
      ptr = cn_gen_alloc(sz);                                                            \
    } else {                                                                             \
      uint8_t null_in_every = get_null_in_every();                                       \
      if (is_sized_null()) {                                                             \
        set_null_in_every(cn_gen_rec_size);                                              \
      }                                                                                  \
      if (cn_gen_failure_get_failure_type() != CN_GEN_BACKTRACK_ALLOC &&                 \
          cn_gen_rec_size <= 1) {                                                        \
        ptr = convert_to_cn_pointer(NULL);                                               \
      } else {                                                                           \
        ptr = cn_gen_alloc(sz);                                                          \
      }                                                                                  \
      if (is_sized_null()) {                                                             \
        set_null_in_every(null_in_every);                                                \
      }                                                                                  \
    }                                                                                    \
    ptr;                                                                                 \
  })

#define CN_GEN_LT_(ty, max) cn_gen_lt_##ty(max)

#define CN_GEN_GT_(ty, min) cn_gen_gt_##ty(min)

#define CN_GEN_LE_(ty, max) cn_gen_max_##ty(max)

#define CN_GEN_GE_(ty, min) cn_gen_min_##ty(min)

#define CN_GEN_RANGE(ty, min, max) cn_gen_range_##ty(min, max)

#define CN_GEN_MULT_RANGE(ty, mul, min, max) cn_gen_mult_range_##ty(mul, min, max)

#define CN_GEN_MULT(ty, mul) cn_gen_mult_##ty(mul)

#define CN_GEN_CALL_FROM(...)                                                            \
  {                                                                                      \
    char* from[] = {__VA_ARGS__, NULL};

#define CN_GEN_CALL_TO(...)                                                              \
  char* to[] = {__VA_ARGS__, NULL};                                                      \
  cn_gen_failure_remap_blamed_many(from, to);                                            \
  }

#define CN_GEN_CALL_PATH_VARS(...)                                                       \
  if (cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_DEPTH) {                     \
    char* toAdd[] = {__VA_ARGS__, NULL};                                                 \
    cn_gen_failure_blame_many(toAdd);                                                    \
  }

#define CN_GEN_ASSIGN(                                                                   \
    pointer, pointer_val, addr, addr_ty, value, tmp, gen_name, last_var, ...)            \
  if (convert_from_cn_pointer(pointer_val) == 0) {                                       \
    cn_gen_failure_blame((char*)#pointer);                                               \
    if (sizeof(addr_ty) > sizeof(intmax_t)) {                                            \
      cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ALLOC);                           \
      cn_gen_failure_set_allocation_needed(sizeof(addr_ty));                             \
    } else {                                                                             \
      cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ALLOC);                           \
      cn_gen_failure_set_allocation_needed(sizeof(intmax_t));                            \
    }                                                                                    \
    goto cn_label_##last_var##_backtrack;                                                \
  }                                                                                      \
  void* tmp##_ptr = convert_from_cn_pointer(addr);                                       \
  if (!cn_gen_alloc_check(tmp##_ptr, sizeof(addr_ty))) {                                 \
    cn_gen_failure_blame((char*)#pointer);                                               \
    size_t tmp##_size = (uintptr_t)tmp##_ptr + sizeof(addr_ty) -                         \
                        (uintptr_t)convert_from_cn_pointer(pointer_val);                 \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ALLOC);                             \
    cn_gen_failure_set_allocation_needed(tmp##_size);                                    \
    goto cn_label_##last_var##_backtrack;                                                \
  }                                                                                      \
  if (!cn_gen_ownership_check(tmp##_ptr, sizeof(addr_ty))) {                             \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ASSERT);                            \
    char* toAdd[] = {__VA_ARGS__};                                                       \
    cn_gen_failure_blame_many(toAdd);                                                    \
    goto cn_label_##last_var##_backtrack;                                                \
  }                                                                                      \
  *(addr_ty*)tmp##_ptr = value;                                                          \
  cn_gen_ownership_update(tmp##_ptr, sizeof(addr_ty));

#define CN_GEN_LET_BEGIN(backtracks, var)                                                \
  int var##_backtracks = backtracks;                                                     \
  cn_bump_frame_id var##_checkpoint = cn_bump_get_frame_id();                            \
  void* var##_alloc_checkpoint = cn_gen_alloc_save();                                    \
  void* var##_ownership_checkpoint = cn_gen_ownership_save();                            \
  cn_label_##var##_gen :;

#define CN_GEN_LET_BODY(ty, var, gen)                                                    \
  cn_gen_rand_checkpoint var##_rand_checkpoint_before = cn_gen_rand_save();              \
  ty* var = gen;                                                                         \
  cn_gen_rand_checkpoint var##_rand_checkpoint_after = cn_gen_rand_save();

#define CN_GEN_LET_END(var, last_var, ...)                                               \
  if (cn_gen_failure_get_failure_type() != CN_GEN_BACKTRACK_NONE) {                      \
    cn_label_##var##_backtrack : CN_GEN_CHECK_TIMEOUT();                                 \
    cn_bump_free_after(var##_checkpoint);                                                \
    cn_gen_alloc_restore(var##_alloc_checkpoint);                                        \
    cn_gen_ownership_restore(var##_ownership_checkpoint);                                \
    if (cn_gen_failure_is_blamed((char*)#var)) {                                         \
      char* toAdd[] = {__VA_ARGS__};                                                     \
      cn_gen_failure_blame_many(toAdd);                                                  \
      if (var##_backtracks <= 0) {                                                       \
        goto cn_label_##last_var##_backtrack;                                            \
      }                                                                                  \
      if (cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_ASSERT ||                \
          cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_DEPTH) {                 \
        var##_backtracks--;                                                              \
        cn_gen_failure_reset();                                                          \
      } else if (cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_ALLOC) {          \
        if (toAdd[0] != NULL) {                                                          \
          goto cn_label_##last_var##_backtrack;                                          \
        }                                                                                \
        if (cn_gen_failure_get_allocation_needed() > 0) {                                \
          cn_gen_rand_restore(var##_rand_checkpoint_after);                              \
        }                                                                                \
      }                                                                                  \
      goto cn_label_##var##_gen;                                                         \
    } else {                                                                             \
      goto cn_label_##last_var##_backtrack;                                              \
    }                                                                                    \
  }

#define CN_GEN_ASSERT(cond, last_var, ...)                                               \
  if (!convert_from_cn_bool(cond)) {                                                     \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_ASSERT);                            \
    char* toAdd[] = {__VA_ARGS__};                                                       \
    cn_gen_failure_blame_many(toAdd);                                                    \
    goto cn_label_##last_var##_backtrack;                                                \
  }

#define CN_GEN_MAP_BEGIN(map, i, i_ty, perm, max, last_var, ...)                         \
  cn_map* map = map_create();                                                            \
  {                                                                                      \
    if (0) {                                                                             \
      cn_label_##i##_backtrack : CN_GEN_CHECK_TIMEOUT();                                 \
      if (cn_gen_failure_is_blamed((char*)#i)) {                                         \
        char* toAdd[] = {__VA_ARGS__};                                                   \
        cn_gen_failure_blame_many(toAdd);                                                \
      }                                                                                  \
      goto cn_label_##last_var##_backtrack;                                              \
    }                                                                                    \
                                                                                         \
    i_ty* i = max;                                                                       \
    while (convert_from_cn_bool(perm)) {                                                 \
    /* Generate each item */

#define CN_GEN_MAP_END(map, i, i_ty, min, val)                                           \
  cn_map_set(map, cast_##i_ty##_to_cn_integer(i), val);                                  \
                                                                                         \
  if (convert_from_cn_bool(i_ty##_equality(i, min))) {                                   \
    break;                                                                               \
  }                                                                                      \
                                                                                         \
  i = i_ty##_sub(i, convert_to_##i_ty(1));                                               \
  }                                                                                      \
  }

#define CN_GEN_PICK_BEGIN(ty, var, tmp, last_var, ...)                                   \
  ty* var = NULL;                                                                        \
  uint64_t tmp##_choices[] = {__VA_ARGS__, UINT64_MAX};                                  \
  uint8_t tmp##_num_choices = 0;                                                         \
  while (tmp##_choices[tmp##_num_choices] != UINT64_MAX) {                               \
    tmp##_num_choices += 2;                                                              \
  }                                                                                      \
  tmp##_num_choices /= 2;                                                                \
  struct cn_gen_int_urn* tmp##_urn = urn_from_array(tmp##_choices, tmp##_num_choices);   \
  cn_bump_frame_id tmp##_checkpoint = cn_bump_get_frame_id();                            \
  void* tmp##_alloc_checkpoint = cn_gen_alloc_save();                                    \
  void* tmp##_ownership_checkpoint = cn_gen_ownership_save();                            \
  cn_label_##tmp##_gen :;                                                                \
  uint64_t tmp = urn_remove(tmp##_urn);                                                  \
  if (0) {                                                                               \
    cn_label_##tmp##_backtrack : CN_GEN_CHECK_TIMEOUT();                                 \
    cn_bump_free_after(tmp##_checkpoint);                                                \
    cn_gen_alloc_restore(tmp##_alloc_checkpoint);                                        \
    cn_gen_ownership_restore(tmp##_ownership_checkpoint);                                \
    if ((cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_ASSERT ||                 \
            cn_gen_failure_get_failure_type() == CN_GEN_BACKTRACK_DEPTH) &&              \
        tmp##_urn->size != 0) {                                                          \
      cn_gen_failure_reset();                                                            \
      goto cn_label_##tmp##_gen;                                                         \
    } else {                                                                             \
      goto cn_label_##last_var##_backtrack;                                              \
    }                                                                                    \
  }                                                                                      \
  switch (tmp) {                                                                         \
  /* Case per choice */

#define CN_GEN_PICK_CASE_BEGIN(index) case index:

#define CN_GEN_PICK_CASE_END(var, e)                                                     \
  var = e;                                                                               \
  break;

#define CN_GEN_PICK_END(tmp)                                                             \
  default:                                                                               \
    printf("Invalid generated value");                                                   \
    assert(false);                                                                       \
    }                                                                                    \
    urn_free(tmp##_urn);

#define CN_GEN_SPLIT_BEGIN(tmp, ...)                                                     \
  int tmp##_backtracks = cn_gen_get_size_split_backtracks_allowed();                     \
  cn_bump_frame_id tmp##_checkpoint = cn_bump_get_frame_id();                            \
  void* tmp##_alloc_checkpoint = cn_gen_alloc_save();                                    \
  void* tmp##_ownership_checkpoint = cn_gen_ownership_save();                            \
  cn_label_##tmp##_gen : {                                                               \
    size_t* vars[] = {__VA_ARGS__};                                                      \
    int count = 0;                                                                       \
    for (int i = 0; vars[i] != NULL; i++) {                                              \
      count += 1;                                                                        \
    }

#define CN_GEN_SPLIT_END(tmp, last_var, ...)                                             \
  if (count >= cn_gen_rec_size) {                                                        \
    cn_gen_failure_set_failure_type(CN_GEN_BACKTRACK_DEPTH);                             \
    char* toAdd[] = {__VA_ARGS__};                                                       \
    cn_gen_failure_blame_many(toAdd);                                                    \
    goto cn_label_##last_var##_backtrack;                                                \
  }                                                                                      \
  cn_gen_split(cn_gen_rec_size - count - 1, vars, count);                                \
  for (int i = 0; i < count; i++) {                                                      \
    *(vars[i]) = *(vars[i]) + 1;                                                         \
  }                                                                                      \
  }                                                                                      \
  if (0) {                                                                               \
    cn_label_##tmp##_backtrack : CN_GEN_CHECK_TIMEOUT();                                 \
    cn_bump_free_after(tmp##_checkpoint);                                                \
    cn_gen_alloc_restore(tmp##_alloc_checkpoint);                                        \
    cn_gen_ownership_restore(tmp##_ownership_checkpoint);                                \
    if (cn_gen_failure_is_blamed(#tmp)) {                                                \
      char* toAdd[] = {__VA_ARGS__};                                                     \
      cn_gen_failure_blame_many(toAdd);                                                  \
      if (tmp##_backtracks <= 0) {                                                       \
        goto cn_label_##last_var##_backtrack;                                            \
      }                                                                                  \
      tmp##_backtracks--;                                                                \
      cn_gen_failure_reset();                                                            \
      goto cn_label_##tmp##_gen;                                                         \
    } else {                                                                             \
      goto cn_label_##last_var##_backtrack;                                              \
    }                                                                                    \
  }

#endif  // CN_GEN_DSL_H
