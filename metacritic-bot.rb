#!/usr/bin/ruby
#encoding: utf-8

require 'mechanize'
require 'twitter'
require 'yaml'
require 'json'
require 'redis'

# Loading latest games scores from Metacritic
agent = Mechanize.new
link = 'http://www.metacritic.com/browse/games/score/metascore/90day/pc'
page = agent.get link
# Array of [Name, Metascore, Userscore, Release_date, Link] vectors
games = page.search('.game_product').map{|e| 
	[e.css('.product_title').text.strip,
	e.css('.metascore_w.positive').text, 
	e.css('.textscore').text, 
	e.css('.release_date>.data').text,
	'http://www.metacritic.com' + e.css('a').attr('href').value]
	}.reject{|e| e[1] == ""}

# Connecting to twitter
twitter_settings = YAML.load_file('twitter-keys.yml')
twitter_client = Twitter::REST::Client.new do |config|
  config.consumer_key        = twitter_settings["consumer_key"]
  config.consumer_secret     = twitter_settings["consumer_secret"]
  config.access_token        = twitter_settings["access_token"]
  config.access_token_secret = twitter_settings["access_token_secret"]
end

redis = Redis.new
games.each{|g| redis.sadd 'mc_new', g.to_json}
redis.sinterstore 'mc_tweeted', 'mc_new', 'mc_tweeted'
redis.sdiffstore 'mc_to_tweet', 'mc_new', 'mc_tweeted'
game = JSON.parse(redis.spop('mc_to_tweet'))
if game[2] != 'tbd'
	texts = []
	texts += ["Check out \"#{game[0]}\". It's metascore - #{game[1]}. Users score - #{game[2]}. It was released on #{game[3]}. #{game[4]}"]
	texts += ["Another good game - \"#{game[0]}\" released on #{game[3]}. Metascore and userscore are - #{game[1]} and #{game[2]} respectively. #{game[4]}"]
	texts += ["\"#{game[0]}\" is out. With #{game[1]} points from critics and #{game[2]} from users. #{game[4]}"]
	texts.shuffle.each do |t|
		begin
			twitter_client.update(t)
			redis.sadd 'mc_tweeted', game.to_json
			break
		rescue
			puts "Problem while sending text: #{t}."
		end
	end
end
