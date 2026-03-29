#!/bin/bash
# generate_spec_doc.sh — Export StrictDoc requirements to HTML
#
# Requires: strictdoc (pip install strictdoc)
# CUSTOMIZE: Adjust the paths below.

strictdoc export docs/requirements --output-dir output
