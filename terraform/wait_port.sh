#!/bin/bash

while ! nc -z $1 $2; do
  sleep 5
done
