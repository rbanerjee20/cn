#include "cerberus.h"
int 
main (void)
{
  int i;
  for (i = 1; i < 100; i++)
    ;
  if (i == 100) 
    exit (0);
  abort ();
}

