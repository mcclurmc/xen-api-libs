(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

type keylogger =
{
	mutable debug: string list;
	mutable info: string list;
	mutable warn: string list;
	mutable error: string list;
	no_default: bool;
}

(* map all logger strings into a logger *)
let __all_loggers = Hashtbl.create 10

(* default logger that everything that doesn't have a key in __lop_mapping get send *)
let __default_logger = { debug = []; info = []; warn = []; error = []; no_default = false }

(*
 * This describe the mapping between a name to a keylogger.
 * a keylogger contains a list of logger string per level of debugging.
 * Example:   "xenops", debug -> [ "stderr"; "/var/log/xensource.log" ]
 *            "xapi", error ->   []
 *            "xapi", debug ->   [ "/var/log/xensource.log" ]
 *            "xenops", info ->  [ "syslog" ]
 *)
let __log_mapping = Hashtbl.create 32

let get_or_open logstring =
	if Hashtbl.mem __all_loggers logstring then
		Hashtbl.find __all_loggers logstring
	else
		let t = Log.of_string logstring in
		Hashtbl.add __all_loggers logstring t;
		t

(** create a mapping entry for the key "name".
 * all log level of key "name" default to "logger" logger.
 * a sensible default is put "nil" as a logger and reopen a specific level to
 * the logger you want to.
 *)
let add key logger =
	let kl = {
		debug = logger;
		info = logger;
		warn = logger;
		error = logger;
		no_default = false;
	} in
	Hashtbl.add __log_mapping key kl

let get_by_level keylog level =
	match level with
	| Log.Debug -> keylog.debug
	| Log.Info  -> keylog.info
	| Log.Warn  -> keylog.warn
	| Log.Error -> keylog.error

let set_by_level keylog level logger =
	match level with
	| Log.Debug -> keylog.debug <- logger
	| Log.Info  -> keylog.info <- logger
	| Log.Warn  -> keylog.warn <- logger
	| Log.Error -> keylog.error <- logger

(** set a specific key|level to the logger "logger" *)
let set key level logger =
	if not (Hashtbl.mem __log_mapping key) then
		add key [];

	let keylog = Hashtbl.find __log_mapping key in
	set_by_level keylog level logger

(** set default logger *)
let set_default level logger =
	set_by_level __default_logger level logger

(** append a logger to the list *)
let append key level logger =
	if not (Hashtbl.mem __log_mapping key) then
		add key [];
	let keylog = Hashtbl.find __log_mapping key in
	let loggers = get_by_level keylog level in
	set_by_level keylog level (loggers @ [ logger ])

(** append a logger to the default list *)
let append_default level logger =
	let loggers = get_by_level __default_logger level in
	set_by_level __default_logger level (loggers @ [ logger ])

(** reopen all logger open *)
let reopen () =
	Hashtbl.iter (fun k v ->
		Hashtbl.replace __all_loggers k (Log.reopen v)) __all_loggers

(** reclaim close all logger open that are not use by any other keys *)
let reclaim () =
	let list_sort_uniq l =
		let oldprev = ref "" and prev = ref "" in
		List.fold_left (fun a k ->
			oldprev := !prev;
			prev := k;
			if k = !oldprev then a else k :: a) []
			(List.sort compare l)
		in
	let flatten_keylogger v =
		list_sort_uniq (v.debug @ v.info @ v.warn @ v.error) in
	let oldkeys = Hashtbl.fold (fun k v a -> k :: a) __all_loggers [] in
	let usedkeys = Hashtbl.fold (fun k v a ->
		(flatten_keylogger v) @ a)
		__log_mapping (flatten_keylogger __default_logger) in
	let usedkeys = list_sort_uniq usedkeys in

	List.iter (fun k ->
		if not (List.mem k usedkeys) then (
			begin try
				Log.close (Hashtbl.find __all_loggers k)
			with
				Not_found -> ()
			end;
			Hashtbl.remove __all_loggers k
		)) oldkeys

(** clear a specific key|level *)
let clear key level =
	try
		let keylog = Hashtbl.find __log_mapping key in
		set_by_level keylog level [];
		reclaim ()
	with Not_found ->
		()

(** clear a specific default level *)
let clear_default level =
	set_default level [];
	reclaim ()

(** reset all the loggers to the specified logger *)
let reset_all logger =
	Hashtbl.clear __log_mapping;
	set_default Log.Debug logger;
	set_default Log.Warn logger;
	set_default Log.Error logger;
	set_default Log.Info logger;
	reclaim ()

(** log a fmt message to the key|level logger specified in the log mapping.
 * if the logger doesn't exist, assume nil logger.
 *)
let log_common key level ?(extra="") ~ret_fn1 ~ret_fn2 (fmt: ('a, unit, string, 'b) format4): 'a =
	let keylog =
		if Hashtbl.mem __log_mapping key then
			let keylog = Hashtbl.find __log_mapping key in
			if keylog.no_default = false &&
			   get_by_level keylog level = [] then
				__default_logger
			else
				keylog
		else
			__default_logger in
	let loggers = get_by_level keylog level in
	match loggers with
	| [] -> Printf.kprintf ret_fn1 fmt
	| _  ->
		let l = List.fold_left (fun acc logger ->	
			try get_or_open logger :: acc
			with _ -> acc
		) [] loggers in
		let l = List.rev l in
		ret_fn2 l

let log key level ?(extra="") (fmt: ('a, unit, string, unit) format4): 'a =
	log_common key level ~extra ~ret_fn1:(ignore) fmt
		~ret_fn2:(fun l ->
    (* ksprintf is the preferred name for kprintf, but the former                                   
     * is not available in OCaml 3.08.3 *)                                                          
    Printf.kprintf (fun s ->
      List.iter (fun t -> Log.output t ~key ~extra level s) l) fmt
		)

let log_and_return key level ?(raw=false) ~syslog_time ?(extra="") (fmt: ('a, unit, string, string) format4): 'a =
	log_common key level ~extra ~ret_fn1:(fun s->s) fmt
    ~ret_fn2:(fun l ->
		let ret_str = ref "" in
    Printf.kprintf (fun s ->
      List.iter (fun t -> ret_str := Log.output_and_return t ~raw ~syslog_time ~key ~extra level s) l; !ret_str) fmt
		)


(* define some convenience functions *)
let debug t ?extra (fmt: ('a , unit, string, unit) format4) =
	log t Log.Debug ?extra fmt
let info t ?extra (fmt: ('a , unit, string, unit) format4) =
	log t Log.Info ?extra fmt
let warn t ?extra (fmt: ('a , unit, string, unit) format4) =
	log t Log.Warn ?extra fmt
let error t ?extra (fmt: ('a , unit, string, unit) format4) =
	log t Log.Error ?extra fmt
let audit t ?raw ?extra (fmt: ('a , unit, string, string) format4) =
  log_and_return t Log.Info ?raw ~syslog_time:true ?extra fmt
