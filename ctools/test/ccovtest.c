#include <stdio.h>
#include <stdlib.h>

void uncalledFunction ()
{
	printf("This line should not execute.");
}

void funct (int i)
{
	if (0 == i || i == 1)
	{
	   printf("Decision and Condition evaluated to TF.");
	}
}

int main(int argc, char **argv)
{
	int a = atoi(argv[1]);	//should be 0
	int b = atoi(argv[2]);  //should be 1
	int c = atoi(argv[3]);  //should be 1

	if (a == b || b == c)
	{
		printf("True decision; True condition; False condition.");
	}

	if (a)
	{
	   if (a == b)
		{
			printf("Unevaluated decision and condition.");
		}
	}
	else
	{
		printf("False Decision.");
	}

	switch (a)
	{
		case 0:  printf("Executed switch case.");
				   break;
		default: printf("Unexecuted switch case.");
				   break;
	}

	funct(a);
	funct(b+c);
}
