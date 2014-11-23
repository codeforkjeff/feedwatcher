
require 'cgi'
require 'net/http'
require 'open-uri'
require 'rss'

module Feedwatcher
  
  # Provides persistent storage of links we've already seen and no
  # longer need to report on
  class LinkStore

    def initialize(db_filename)
      @db_filename = File.expand_path(db_filename)
      @links = Hash.new

      if File.exist? @db_filename
        File.open(@db_filename) do |file|
          while line = file.gets do
            url, timestamp  = line.chomp.split
            # only keep URLs that aren't too old; this trims down the
            # list every time we open the file
            if !too_old?(timestamp.to_i)
              @links[url] = timestamp
            end
          end
        end
      end
    end

    def too_old?(ts)
      # 172800 = 48h
      Time.now.to_i - ts > 172800
    end

    def seen?(link)
      @links.has_key? link
    end

    def add(link, timestamp)
      @links[link] = timestamp
    end

    # save the URLs we've encountered to a file
    def persist
      File.open(@db_filename, "w") do |file|
        @links.each do |url, timestamp|
          file.puts(url + ' ' + timestamp.to_i.to_s)
        end
      end
    end

  end


  # encapsulates a Match by containing both the matching feed item and
  # the human-readable labels for the regexes that matched
  class Match

    attr_accessor :feed_item
    attr_accessor :labels

    # Construct a new Match containing feed_item, and add it to matches
    def initialize(feed_item, matches)
      @feed_item = feed_item
      @labels = []
      matches << self
    end

  end


  # Searches the contents of one or more feeds for passed-in search patterns
  class Search

    def initialize(patterns, feed_urls, link_store, feed_cache)
      @patterns = patterns
      @feed_urls = feed_urls
      @link_store = link_store
      @feed_cache = feed_cache
      @matches = Array.new
    end

    # scan feeds and populate 'matches'
    def scan
      @feed_urls.each do |feed_url|
        scan_url(feed_url, @patterns)
      end
    end

    # returns str report of matches
    def output
      output = ''
      @matches.each do |match|
        output << CGI.unescapeHTML(match.feed_item.title)
        output << "\n"
        output << match.feed_item.link
        output << "\n"
        output << '(Matches: ' + match.labels.join(', ') + ')'
        output << "\n\n"
      end
      output
    end

    private

    # returns Feed object. this caches.
    def get_feed(feed_url)
      if !@feed_cache.has_key?(feed_url)

        rssdata = ''

        open(feed_url) {|f|
          rssdata = f.read
        }

        # specifying only 'UTF-8' doesn't prevent errors in RSS::Parser,
        # we seem to need to specify 'binary' as the src encoding
        rssdata.encode!('UTF-8', 'binary', :invalid => :replace, :undef => :replace, :replace => '?')

        begin
          @feed_cache[feed_url] = RSS::Parser.parse(rssdata)
        rescue
          puts "Error parsing, here's the data: #{rssdata}"
          raise
        end

      end
      @feed_cache[feed_url]
    end

    # if the given link has previously matched, return the Match object
    # for it
    def get_previous_match(link)
      @matches.find { |match| match.feed_item.link == link }
    end

    # scan the feed_url for regexes in the patterns hash
    def scan_url(feed_url, patterns)

      feed = get_feed(feed_url)

      feed.items.each do |feed_item|
        link = feed_item.link
        title = CGI.unescapeHTML(feed_item.title)
        if !@link_store.seen?(link)
          #puts "examining ", feed_item.title

          @patterns.each do |label, regex|
            if feed_item.content_encoded =~ regex || title =~ regex
              #puts "MATCH for ", label
              match = get_previous_match(link) || Match.new(feed_item, @matches)
              match.labels << label
            end
          end

          @link_store.add(link, feed_item.date.to_i)
        end
      end

    end

  end

end


if __FILE__ == $PROGRAM_NAME

  config_path = File.expand_path("~/.feedwatcher.conf")

  if !File.exist?(config_path)
    puts "Error: #{config_path} doesn't exist. create it."
    exit 1
  end
  
  searches = nil
  
  open(File.expand_path(config_path)) do |f|
    # eval is evil, but this will do until I can create a DSL or
    # something for configuration
    searches = eval(f.read())
  end

  if searches.nil?
    puts "Error: config file didn't return a data structure describing searches. Check #{config_path}"
    exit 1
  end
  
  feed_cache = Hash.new
  link_store = Feedwatcher::LinkStore.new('~/.feedwatcher.dat')

  begin

    output = ''
    searches.each do |search|
      feed_watcher = Feedwatcher::Search.new(search[:patterns], search[:feed_urls], link_store, feed_cache)
      feed_watcher.scan
      output << feed_watcher.output
    end

    puts output if output.length > 0

    link_store.persist

  rescue Exception => e
    # print errors to stdout
    puts "Error occurred in script: #{e.to_s}"
    puts e.backtrace
  end

end
