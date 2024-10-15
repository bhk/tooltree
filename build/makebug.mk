# Make 3.81 reports no error when building this, but exist with error code 2.
# It *does* report an error if two different non-existent prereqs are named.
target : does-not-exist ; echo $@
INC : does-not-exist ; echo $@
-include INC
