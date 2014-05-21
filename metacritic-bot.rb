#!/usr/bin/ruby
#encoding: utf-8

require 'mechanize'
require 'twitter'
require 'yaml'
require 'json'
require 'redis'

$redis = Redis.new

def post_tweet_wo_auth(login, password, tweet_text)
	a = Mechanize.new
	# logging in
	p = a.get('https://m.twitter.com')
	p.form['username'] = "#{login}"
	p.form['password'] = "#{password}"
	p.form.submit

	# tweeting
	p = a.get('https://mobile.twitter.com/compose/tweet')
	p.form['tweet[text]'] = "#{tweet_text}"
	p.form.submit
end

def post_tweet_api(tweet_text)
	# Connecting to twitter api
	twitter_settings = YAML.load_file('twitter-keys.yml')
	twitter_client = Twitter::REST::Client.new do |config|
	  config.consumer_key        = twitter_settings["consumer_key"]
	  config.consumer_secret     = twitter_settings["consumer_secret"]
	  config.access_token        = twitter_settings["access_token"]
	  config.access_token_secret = twitter_settings["access_token_secret"]
	end

	twitter_client.update(t)
end

def get_games
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
	return games
end

def redis_mc_initialize
	['mc_to_tweet', 'mc_new', 'mc_tweeted'].each{|key| $redis.del key}
	games = get_games
	games.each{|g| $redis.sadd 'mc_tweeted', g[0]}
end

creds = YAML.load_file('creds.yml')
games = get_games
games.each{|g| $redis.sadd 'mc_new', g[0]}
$redis.sinterstore 'mc_tweeted', 'mc_new', 'mc_tweeted'
$redis.sdiffstore 'mc_to_tweet', 'mc_new', 'mc_tweeted'
game_name = $redis.spop('mc_to_tweet')
game = games.find{|g| g[0] == game_name}
if game[2] != 'tbd'
	texts = []
	texts += ["Check out \"#{game[0]}\". It's metascore - #{game[1]}. Users score - #{game[2]}. It was released on #{game[3]}. #{game[4]}"]
	texts += ["Another good game - \"#{game[0]}\" released on #{game[3]}. Metascore and userscore are - #{game[1]} and #{game[2]} respectively. #{game[4]}"]
	texts += ["\"#{game[0]}\" is out. With #{game[1]} from critics and #{game[2]} from users. #{game[4]}"]
	texts.shuffle.each do |t|
		begin
			post_tweet_wo_auth("#{creds["login"]}", "#{creds["password"]}", t)
			$redis.sadd 'mc_tweeted', game
			break
		rescue Exception => e
			puts "Problem while sending text: #{t}."
			puts e
		end
	end
end