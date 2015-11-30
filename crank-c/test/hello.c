#include <stdio.h>

#include "foo.h"

int main(int argc, char **argv)
{
   const char *s = foo();

   (void) argc;
   (void) argv;

   return (*s == 'x' ? 0 : 1);
}
