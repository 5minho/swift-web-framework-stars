#!/bin/sh
git pull origin master
swift list2md.swift
git commit -m "Auto update" -a
git push origin master
