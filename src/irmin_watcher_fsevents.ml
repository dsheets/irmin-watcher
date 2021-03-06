(*---------------------------------------------------------------------------
   Copyright (c) 2016 Thomas Gazagnaire. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

open Lwt.Infix

let src = Logs.Src.create "irw-fsevents" ~doc:"Irmin watcher using FSevents"
module Logs = (val Logs.src_log src : Logs.LOG)

let create_flags = Fsevents.CreateFlags.detailed_interactive
let run_loop_mode = Cf.RunLoop.Mode.Default

let listen dir fn =
  let watcher = Fsevents_lwt.create 0. create_flags [dir] in
  let stream = Fsevents_lwt.stream watcher in
  let event_stream = Fsevents_lwt.event_stream watcher in
  let path_of_event { Fsevents_lwt.path; _ } = path in
  let iter () = Lwt_stream.iter_s (fun e ->
      let path = path_of_event e in
      Logs.debug (fun l -> l "fsevents: %s" path);
      fn @@ path
    ) stream
  in
  Cf_lwt.RunLoop.run_thread (fun runloop ->
      Fsevents.schedule_with_run_loop event_stream runloop run_loop_mode;
      if not (Fsevents.start event_stream)
      then prerr_endline "failed to start FSEvents stream")
  >|= fun _scheduler ->
  let stop_iter = Irmin_watcher_core.stoppable iter in
  let stop_scheduler () =
    (* Fsevents_lwt.flush watcher >>= fun () ->*)
    Fsevents_lwt.stop watcher;
    Fsevents_lwt.invalidate watcher;
    Fsevents_lwt.release watcher
  in
  fun () ->
    stop_iter ();
    stop_scheduler ()

let t = Irmin_watcher_core.Watchdog.empty ()

(* Note: we use FSevents to detect any change, and we re-read the full
   tree on every change (so very similar to active polling, but
   blocking on incoming FSevents instead of sleeping). We could
   probably do better, but at the moment it is more robust to do so,
   to avoid possible duplicated events. *)
let hook =
  let open Irmin_watcher_core in
  let wait_for_changes dir () =
    let t, u = Lwt.task () in
    listen dir (fun _path -> Lwt.wakeup u (); Lwt.return_unit) >>= fun u ->
    t >|= fun () ->
    u ()
  in
  let listen dir f =
    Logs.info (fun l -> l "FSevents mode");
    Irmin_watcher_polling.listen ~wait_for_changes:(wait_for_changes dir) ~dir f
  in
  create t listen

(*---------------------------------------------------------------------------
   Copyright (c) 2016 Thomas Gazagnaire

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
