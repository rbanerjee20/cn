#include "cerberus.h"
int 
main (void)
{
  unsigned long val = 1;

  if (val > (unsigned long) ~0)
    abort();
  exit (0);
}
