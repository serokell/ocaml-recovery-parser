# Copyright (c) 2019 Frédéric Bour
#
# SPDX-License-Identifier: MIT

all:
	dune build example/ocaml/recovery_parser.cma

clean:
	dune clean
