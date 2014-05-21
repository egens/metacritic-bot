#!/usr/bin/env bash

echo 'Started shell script' > log

# load rvm ruby
source /home/egens/.rvm/environments/ruby-2.1.0

ruby metacritic-bot.rb > log
