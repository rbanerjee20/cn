#include "cerberus.h"

unsigned int test (unsigned int x)
{
  return x / 0x80000001U / 0x00000002U;
}

int 
main (void)
{
  if (test(2) != 0)
    abort ();
  return 0;
}
