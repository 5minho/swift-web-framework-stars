#!/bin/sh
git pull
swift list2md.swift
git commit -m "Auto update" -a
git push origin
