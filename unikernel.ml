(*
 * Copyright (c) 2015 Magnus Skjegstad <magnus@skjegstad.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Lwt 
open Printf
open String
open Conduit
open Cstruct

module Main (C : V1_LWT.CONSOLE)(N : V1_LWT.NETWORK) = struct
  cstruct arpip {
    uint8_t        mac[6];
    uint32_t       ip
  } as big_endian

  module E = Ethif.Make(N)
  module S = struct
      module I = Ipv4.Make(E)(Clock)(OS.Time)
      module U = Udp.Make(I)
      module T = Tcp.Flow.Make(I)(OS.Time)(Clock)(Random)
      module S = Tcpip_stack_direct.Make(C)(OS.Time)(Random)(N)(E)(I)(U)(T)
      include S
  end
  module Garp = Garp.Make(E)

  module CON = Conduit_mirage.Make(S)(Conduit_xenstore)(Conduit_mirage.No_TLS)

  let or_error name fn t =
    fn t
    >>= function
        | `Error e -> fail (Failure ("Error starting " ^ name))
        | `Ok t -> return t 

  let listen_callback c ethif flow ic oc = 
    C.log_s c "Client connected." >>= fun () ->
    let rec print () =
        CON.Flow.read flow >>= fun r ->
        match r with
        | `Ok buf -> 
                let ip = Ipaddr.V4.of_int32 (get_arpip_ip buf) in
                let mac = Macaddr.of_bytes (Cstruct.to_string (get_arpip_mac buf)) in
                (match mac with
                | None -> C.log_s c "Unable to parse ARP data. Internal error."
                | Some m -> C.log_s c (Printf.sprintf "Got mac=%s for ip=%s" (Macaddr.to_string m) (Ipaddr.V4.to_string ip)) >>= fun () -> 
                        Garp.output_garp ethif m [ip]
                ) >>= fun () -> print ()
        | `Eof -> C.log_s c "Connection closed."
        | `Error msg -> C.log_s c (Printf.sprintf "Error: %s" (CON.Flow.error_message msg))
    in
    print ()

  let conduit_serve c ethif callback () =
    let port_s = "synjitsu" in
    match Vchan.Port.of_string port_s with
    | `Ok port -> let server = `Vchan_direct (`Remote_domid 0, port) in
                  C.log_s c "Initializing conduit" >>= fun () ->
                  CON.init () >>= fun ctx ->
                  C.log_s c (Printf.sprintf "Listening for connections from dom 0 on port '%s'" port_s) >>= fun () ->
                  Conduit_xenstore.register "synjitsu" >>= fun t ->
                  let rec aux () = 
                      CON.serve ~ctx ~mode:server (callback c ethif) >>= fun () ->
                      C.log_s c "Serve exited. Restarting." >>= fun () ->
                      aux () in
                  aux ()
    | `Error s -> raise_lwt (Failure s)

  let start c n =
    E.connect n >>= fun ethif ->
    match ethif with
    | `Error err -> C.log_s c "Unable to connect to Ethif. Exiting"
    | `Ok ethif -> 
            begin
                let rec tick i () =
                    OS.Time.sleep 10.0 >>= fun () ->
                    Printf.printf ".";
                    tick (i+1) () in

                OS.Time.sleep 2.0 >>= fun () ->
                Lwt.join [
                    tick 0 () ;
                    conduit_serve c ethif listen_callback ()
                  ]
            end 
    >>= fun () ->
    Lwt.return_unit (* exit cleanly *)

end
