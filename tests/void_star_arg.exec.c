#define __CN_INSTRUMENT
#include <cn-executable/utils.h>
#include <cn-executable/cerb_types.h>
typedef __cerbty_intptr_t intptr_t;
typedef __cerbty_uintptr_t uintptr_t;
typedef __cerbty_intmax_t intmax_t;
typedef __cerbty_uintmax_t uintmax_t;
static const int __cerbvar_INT_MAX = 0x7fffffff;
static const int __cerbvar_INT_MIN = ~0x7fffffff;

/* ORIGINAL C STRUCTS */

struct two_ints {
  signed int x;
  signed int y;
};


/* CN RECORDS */

struct Tagged_Pointer_record {
  cn_bits_i32* k;
};

/* CN VERSIONS OF C STRUCTS */

struct two_ints_cn {
  cn_bits_i32* x;
  cn_bits_i32* y;
};



/* OWNERSHIP FUNCTIONS */

static cn_bits_i32* owned_signed_int(cn_pointer*, enum spec_mode);
static struct two_ints_cn* owned_struct_two_ints(cn_pointer*, enum spec_mode);
/* CONVERSION FUNCTIONS */

/* GENERATED STRUCT FUNCTIONS */

static struct two_ints_cn* default_struct_two_ints_cn();
static void* cn_map_get_struct_two_ints_cn(cn_map*, cn_integer*);
static cn_bool* struct_two_ints_cn_equality(void*, void*);
static struct two_ints convert_from_struct_two_ints_cn(struct two_ints_cn*);
static struct two_ints_cn* convert_to_struct_two_ints_cn(struct two_ints);
/* RECORD FUNCTIONS */
static cn_bool* struct_Tagged_Pointer_record_equality(void*, void*);
static struct Tagged_Pointer_record* default_struct_Tagged_Pointer_record();
static void* cn_map_get_struct_Tagged_Pointer_record(cn_map*, cn_integer*);
/* CN FUNCTIONS */

static cn_bool* addr_eq(cn_pointer*, cn_pointer*);
static cn_bool* prov_eq(cn_pointer*, cn_pointer*);
static cn_bool* ptr_eq(cn_pointer*, cn_pointer*);
static cn_bool* is_null(cn_pointer*);
static cn_bool* not(cn_bool*);
static cn_bits_u8* MINu8();
static cn_bits_u8* MAXu8();
static cn_bits_u16* MINu16();
static cn_bits_u16* MAXu16();
static cn_bits_u32* MINu32();
static cn_bits_u32* MAXu32();
static cn_bits_u64* MINu64();
static cn_bits_u64* MAXu64();
static cn_bits_i8* MINi8();
static cn_bits_i8* MAXi8();
static cn_bits_i16* MINi16();
static cn_bits_i16* MAXi16();
static cn_bits_i32* MINi32();
static cn_bits_i32* MAXi32();
static cn_bits_i64* MINi64();
static cn_bits_i64* MAXi64();

static struct Tagged_Pointer_record* Tagged_Pointer(cn_pointer*, cn_bits_i32*, enum spec_mode);
#ifndef offsetof
#define offsetof(st, m) ((__cerbty_size_t)((char *)&((st *)0)->m - (char *)0))
#endif
#pragma GCC diagnostic ignored "-Wattributes"

/* GLOBAL ACCESSORS */
void* memcpy(void* dest, const void* src, __cerbty_size_t count );

// Some gcc builtins we support
[[ cerb::hidden ]] int __builtin_ffs (int x);
[[ cerb::hidden ]] int __builtin_ffsl (long x);
[[ cerb::hidden ]] int __builtin_ffsll (long long x);
[[ cerb::hidden ]] int __builtin_ctz (unsigned int x);
[[ cerb::hidden ]] int __builtin_ctzl (unsigned long x);
[[ cerb::hidden ]] int __builtin_ctzll (unsigned long long x);
[[ cerb::hidden ]] __cerbty_uint16_t __builtin_bswap16 (__cerbty_uint16_t x);
[[ cerb::hidden ]] __cerbty_uint32_t __builtin_bswap32 (__cerbty_uint32_t x);
[[ cerb::hidden ]] __cerbty_uint64_t __builtin_bswap64 (__cerbty_uint64_t x);
[[ cerb::hidden ]] void __builtin_unreachable(void);
// this is an optimisation hint that we can erase
struct two_ints;
/* FIXME: better syntax for else-if, and for checking a pointer
   is correctly aligned to point at a particular type */
/*@
predicate {i32 k} Tagged_Pointer (pointer p, i32 k) {
  if (k == 0i32) {
    return {k: k};
  }
  else { if (k == 1i32) {
    assert (mod((u64)p, ((u64) (sizeof<int>))) == 0u64);
    take V = RW<int>(p);
    return {k: k};
  }
  else {
    assert (k == 2i32);
    assert (mod((u64)p, ((u64) (sizeof<struct two_ints>))) == 0u64);
    take V = RW<struct two_ints>(p);
    return {k: k};
  } }
}
@*/
int
f (void *p, int k)
/*@ requires take X = Tagged_Pointer (p, k);
    ensures take X2 = Tagged_Pointer (p, k); @*/
{
  /* EXECUTABLE CN PRECONDITION */
cn_bump_frame_id cn_frame_id = cn_bump_get_frame_id();
  signed int __cn_ret;
  ghost_stack_depth_incr();
  cn_pointer* p_cn = convert_to_cn_pointer(p);
  cn_bits_i32* k_cn = convert_to_cn_bits_i32(k);
  update_cn_error_message_info("  }\n                  ^cn/void_star_arg.c:39:19:");
  struct Tagged_Pointer_record* X_cn = Tagged_Pointer(p_cn, k_cn, PRE);
  cn_pop_msg_info();
  
	/* C OWNERSHIP */

  c_add_to_ghost_state((&p), sizeof(void*), get_cn_stack_depth());
  cn_pointer* p_addr_cn = convert_to_cn_pointer((&p));
  c_add_to_ghost_state((&k), sizeof(signed int), get_cn_stack_depth());
  cn_pointer* k_addr_cn = convert_to_cn_pointer((&k));
  
  int *p2;
c_add_to_ghost_state((&p2), sizeof(signed int*), get_cn_stack_depth());


cn_pointer* p2_addr_cn = convert_to_cn_pointer((&p2));

  struct two_ints *p3;
c_add_to_ghost_state((&p3), sizeof(struct two_ints*), get_cn_stack_depth());


cn_pointer* p3_addr_cn = convert_to_cn_pointer((&p3));

  if (CN_LOAD(k) == 0) {
    { __cn_ret = 0; 
c_remove_from_ghost_state((&p2), sizeof(signed int*));


c_remove_from_ghost_state((&p3), sizeof(struct two_ints*));
goto __cn_epilogue; }
  }
  else if (CN_LOAD(k) == 1) {
    CN_STORE(p2, CN_LOAD(p));
    { __cn_ret = CN_LOAD(*CN_LOAD(p2)); 
c_remove_from_ghost_state((&p2), sizeof(signed int*));


c_remove_from_ghost_state((&p3), sizeof(struct two_ints*));
goto __cn_epilogue; }
  }
  else if (CN_LOAD(k) == 2) {
    CN_STORE(p3, CN_LOAD(p));
    { __cn_ret = (CN_LOAD(CN_LOAD(p3)->x) < CN_LOAD(CN_LOAD(p3)->y)) ? 1 : 0; 
c_remove_from_ghost_state((&p2), sizeof(signed int*));


c_remove_from_ghost_state((&p3), sizeof(struct two_ints*));
goto __cn_epilogue; }
  }
  else {
    update_cn_error_message_info("{\n       ^~~~~~~~~~~~~~~~~~ cn/void_star_arg.c:56:8-26");

update_cn_error_message_info("{\n        ^~~~~~~~~~~~~~~ cn/void_star_arg.c:56:9-24");

update_cn_error_message_info("{\n        ^~~~~~~~~~~~~~~ cn/void_star_arg.c:56:9-24");

cn_assert(convert_to_cn_bool(false), STATEMENT);

cn_pop_msg_info();

cn_pop_msg_info();

cn_pop_msg_info();

    { __cn_ret = 0; 
c_remove_from_ghost_state((&p2), sizeof(signed int*));


c_remove_from_ghost_state((&p3), sizeof(struct two_ints*));
goto __cn_epilogue; }
  }

c_remove_from_ghost_state((&p2), sizeof(signed int*));


c_remove_from_ghost_state((&p3), sizeof(struct two_ints*));

/* EXECUTABLE CN POSTCONDITION */
__cn_epilogue:

  
	/* C OWNERSHIP */


  c_remove_from_ghost_state((&p), sizeof(void*));

  c_remove_from_ghost_state((&k), sizeof(signed int));

{
  cn_bits_i32* return_cn = convert_to_cn_bits_i32(__cn_ret);
  update_cn_error_message_info("  else if (k == 1) {\n                 ^cn/void_star_arg.c:40:18:");
  struct Tagged_Pointer_record* X2_cn = Tagged_Pointer(p_cn, k_cn, POST);
  cn_pop_msg_info();
  ghost_stack_depth_decr();
  cn_postcondition_leak_check();
}

cn_bump_free_after(cn_frame_id);

return __cn_ret;

}
int main(void)
/*@ trusted; @*/
{
  /* EXECUTABLE CN PRECONDITION */
cn_bump_frame_id cn_frame_id = cn_bump_get_frame_id();
  signed int __cn_ret = 0;
  initialise_ownership_ghost_state();
  initialise_ghost_stack_depth();
  
  struct two_ints two_ints = {.x = 4, .y = 5};
c_add_to_ghost_state((&two_ints), sizeof(struct two_ints), get_cn_stack_depth());


cn_pointer* two_ints_addr_cn = convert_to_cn_pointer((&two_ints));

  int r = f(&two_ints, 2);
c_add_to_ghost_state((&r), sizeof(signed int), get_cn_stack_depth());


cn_pointer* r_addr_cn = convert_to_cn_pointer((&r));


c_remove_from_ghost_state((&two_ints), sizeof(struct two_ints));


c_remove_from_ghost_state((&r), sizeof(signed int));

/* EXECUTABLE CN POSTCONDITION */
__cn_epilogue:

cn_bump_free_after(cn_frame_id);

return __cn_ret;

}

/* RECORD */
cn_bool* struct_Tagged_Pointer_record_equality(void* x, void* y)
{
  struct Tagged_Pointer_record* x_cast = (struct Tagged_Pointer_record*) x;
  struct Tagged_Pointer_record* y_cast = (struct Tagged_Pointer_record*) y;
  return cn_bool_and(convert_to_cn_bool(true), cn_bits_i32_equality(x_cast->k, y_cast->k));
}

struct Tagged_Pointer_record* default_struct_Tagged_Pointer_record()
{
  struct Tagged_Pointer_record* a_1049 = (struct Tagged_Pointer_record*) cn_bump_malloc(sizeof(struct Tagged_Pointer_record));
  a_1049->k = default_cn_bits_i32();
  return a_1049;
}

void* cn_map_get_struct_Tagged_Pointer_record(cn_map* m, cn_integer* key)
{
  void* ret = ht_get(m, (&key->val));
  if (0 == ret)
    return (void*) default_struct_Tagged_Pointer_record();
  else
    return ret;
}
/* CONVERSION */

/* GENERATED STRUCT FUNCTIONS */

static struct two_ints_cn* default_struct_two_ints_cn()
{
  struct two_ints_cn* a_1014 = (struct two_ints_cn*) cn_bump_malloc(sizeof(struct two_ints_cn));
  a_1014->x = default_cn_bits_i32();
  a_1014->y = default_cn_bits_i32();
  return a_1014;
}
static void* cn_map_get_struct_two_ints_cn(cn_map* m, cn_integer* key)
{
  void* ret = ht_get(m, (&key->val));
  if (0 == ret)
    return (void*) default_struct_two_ints_cn();
  else
    return ret;
}
static cn_bool* struct_two_ints_cn_equality(void* x, void* y)
{
  struct two_ints_cn* x_cast = (struct two_ints_cn*) x;
  struct two_ints_cn* y_cast = (struct two_ints_cn*) y;
  return cn_bool_and(cn_bool_and(convert_to_cn_bool(true), cn_bits_i32_equality(x_cast->x, y_cast->x)), cn_bits_i32_equality(x_cast->y, y_cast->y));
}
static struct two_ints convert_from_struct_two_ints_cn(struct two_ints_cn* two_ints)
{
  struct two_ints res;
  res.x = convert_from_cn_bits_i32(two_ints->x);
  res.y = convert_from_cn_bits_i32(two_ints->y);
  return res;
}
static struct two_ints_cn* convert_to_struct_two_ints_cn(struct two_ints two_ints)
{
  struct two_ints_cn* res = (struct two_ints_cn*) cn_bump_malloc(sizeof(struct two_ints_cn));
  res->x = convert_to_cn_bits_i32(two_ints.x);
  res->y = convert_to_cn_bits_i32(two_ints.y);
  return res;
}
/* OWNERSHIP FUNCTIONS */

/* OWNERSHIP FUNCTIONS */

static cn_bits_i32* owned_signed_int(cn_pointer* cn_ptr, enum spec_mode spec_mode)
{
  void* generic_c_ptr = (void*) (signed int*) cn_ptr->ptr;
  cn_get_or_put_ownership(spec_mode, generic_c_ptr, sizeof(signed int));
  return convert_to_cn_bits_i32((*(signed int*) cn_ptr->ptr));
}
static struct two_ints_cn* owned_struct_two_ints(cn_pointer* cn_ptr, enum spec_mode spec_mode)
{
  void* generic_c_ptr = (void*) (struct two_ints*) cn_ptr->ptr;
  cn_get_or_put_ownership(spec_mode, generic_c_ptr, sizeof(struct two_ints));
  return convert_to_struct_two_ints_cn((*(struct two_ints*) cn_ptr->ptr));
}
/* CN FUNCTIONS */
static cn_bool* addr_eq(cn_pointer* arg1, cn_pointer* arg2)
{
  return cn_bits_u64_equality(cast_cn_pointer_to_cn_bits_u64(arg1), cast_cn_pointer_to_cn_bits_u64(arg2));
}
static cn_bool* prov_eq(cn_pointer* arg1, cn_pointer* arg2)
{
  return cn_alloc_id_equality(convert_to_cn_alloc_id(0), convert_to_cn_alloc_id(0));
}
static cn_bool* ptr_eq(cn_pointer* arg1, cn_pointer* arg2)
{
  return cn_pointer_equality(arg1, arg2);
}
static cn_bool* is_null(cn_pointer* arg)
{
  return cn_pointer_equality(arg, convert_to_cn_pointer(0));
}
static cn_bool* not(cn_bool* arg)
{
  return cn_bool_not(arg);
}
static cn_bits_u8* MINu8()
{
  return convert_to_cn_bits_u8(0UL);
}
static cn_bits_u8* MAXu8()
{
  return convert_to_cn_bits_u8(255UL);
}
static cn_bits_u16* MINu16()
{
  return convert_to_cn_bits_u16(0ULL);
}
static cn_bits_u16* MAXu16()
{
  return convert_to_cn_bits_u16(65535ULL);
}
static cn_bits_u32* MINu32()
{
  return convert_to_cn_bits_u32(0ULL);
}
static cn_bits_u32* MAXu32()
{
  return convert_to_cn_bits_u32(4294967295ULL);
}
static cn_bits_u64* MINu64()
{
  return convert_to_cn_bits_u64(0ULL);
}
static cn_bits_u64* MAXu64()
{
  return convert_to_cn_bits_u64(18446744073709551615ULL);
}
static cn_bits_i8* MINi8()
{
  return convert_to_cn_bits_i8((-127L - 1L));
}
static cn_bits_i8* MAXi8()
{
  return convert_to_cn_bits_i8(127L);
}
static cn_bits_i16* MINi16()
{
  return convert_to_cn_bits_i16((-32767LL - 1LL));
}
static cn_bits_i16* MAXi16()
{
  return convert_to_cn_bits_i16(32767LL);
}
static cn_bits_i32* MINi32()
{
  return convert_to_cn_bits_i32((-2147483647LL - 1LL));
}
static cn_bits_i32* MAXi32()
{
  return convert_to_cn_bits_i32(2147483647LL);
}
static cn_bits_i64* MINi64()
{
  return convert_to_cn_bits_i64((-9223372036854775807LL - 1LL));
}
static cn_bits_i64* MAXi64()
{
  return convert_to_cn_bits_i64(9223372036854775807LL);
}


/* CN PREDICATES */

static struct Tagged_Pointer_record* Tagged_Pointer(cn_pointer* p, cn_bits_i32* k, enum spec_mode spec_mode)
{
  if (convert_from_cn_bool(cn_bits_i32_equality(k, convert_to_cn_bits_i32(0LL)))) {
    struct Tagged_Pointer_record* a_911 = (struct Tagged_Pointer_record*) cn_bump_malloc(sizeof(struct Tagged_Pointer_record));
    a_911->k = k;
    return a_911;
  }
  else {
    if (convert_from_cn_bool(cn_bits_i32_equality(k, convert_to_cn_bits_i32(1LL)))) {
      update_cn_error_message_info("    return {k: k};\n    ^~~~~~~~~~~~~~ cn/void_star_arg.c:25:5-27:18");
      cn_assert(cn_bits_u64_equality(cn_bits_u64_mod(cast_cn_pointer_to_cn_bits_u64(p), cast_cn_bits_u64_to_cn_bits_u64(convert_to_cn_bits_u64(sizeof(signed int)))), convert_to_cn_bits_u64(0ULL)), spec_mode);
      cn_pop_msg_info();
      update_cn_error_message_info("  } }\n         ^cn/void_star_arg.c:26:10:");
      cn_bits_i32* V = owned_signed_int(p, spec_mode);
      cn_pop_msg_info();
      update_cn_error_message_info("other_location(File 'lib/compile.ml', line 1124, characters 31-38)");
      cn_assert(convert_to_cn_bool(true), spec_mode);
      cn_pop_msg_info();
      struct Tagged_Pointer_record* a_936 = (struct Tagged_Pointer_record*) cn_bump_malloc(sizeof(struct Tagged_Pointer_record));
      a_936->k = k;
      return a_936;
    }
    else {
      update_cn_error_message_info("int\n    ^cn/void_star_arg.c:30:5-33:18");
      cn_assert(cn_bits_i32_equality(k, convert_to_cn_bits_i32(2LL)), spec_mode);
      cn_pop_msg_info();
      update_cn_error_message_info("f (void *p, int k)\n    ^~~~~~~~~~~~~~ cn/void_star_arg.c:31:5-33:18");
      cn_assert(cn_bits_u64_equality(cn_bits_u64_mod(cast_cn_pointer_to_cn_bits_u64(p), cast_cn_bits_u64_to_cn_bits_u64(convert_to_cn_bits_u64(sizeof(struct two_ints)))), convert_to_cn_bits_u64(0ULL)), spec_mode);
      cn_pop_msg_info();
      update_cn_error_message_info("/*@ requires take X = Tagged_Pointer (p, k);\n         ^cn/void_star_arg.c:32:10:");
      struct two_ints_cn* V = owned_struct_two_ints(p, spec_mode);
      cn_pop_msg_info();
      update_cn_error_message_info("other_location(File 'lib/compile.ml', line 1124, characters 31-38)");
      cn_assert(convert_to_cn_bool(true), spec_mode);
      cn_pop_msg_info();
      struct Tagged_Pointer_record* a_967 = (struct Tagged_Pointer_record*) cn_bump_malloc(sizeof(struct Tagged_Pointer_record));
      a_967->k = k;
      return a_967;
    }
  }
}
