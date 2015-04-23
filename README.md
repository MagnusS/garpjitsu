This unikernel sends gARP on behalf of unikernels booted by [Jitsu](http://github.com/MagnusS/jitsu). It listens for ARP/IP pairs from Jitsu using Conduit and Vchan_direct on port "synjitsu". It is intended to be used with the --synjitsu= option in Jitsu.  

This code should eventually be merged with [Synjitsu](http://github.com/samoht/synjitsu).
