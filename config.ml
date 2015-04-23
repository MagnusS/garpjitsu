open Mirage

let main = foreign "Unikernel.Main" (console @-> network @-> job)

let platform =
    match get_mode () with
        | `Xen -> "xen"
        | _ -> "unix"

let () =
    add_to_opam_packages [
        "conduit" ;
        "cstruct" ;
        "mirage-vnetif" ;
        "mirage-net-" ^ platform;
        "mirage-clock-" ^ platform;
        "mirage-" ^ platform;
        "mirage-types" ;
        "tcpip" ];
    add_to_ocamlfind_libraries [ 
        "cstruct" ;
        "cstruct.syntax" ;
        "conduit" ;
        "conduit.mirage-xen" ;
        "mirage-vnetif" ; 
        "mirage-net-" ^ platform ; 
        "mirage-" ^ platform; 
        "mirage-clock-" ^ platform;
        "tcpip.stack-direct" ; 
        "mirage-types" ];
  register "unikernel" [
    main $ default_console $ tap0
  ]
