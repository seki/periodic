require 'json'
require 'monitor'
require 'set'
require_relative 'bucket'
require 'time'
require 'date'

module Periodic
  Store = Bucket.new

  class Doc
    include MonitorMixin
    def self.load_s3
      begin
        it = Store.get_object(Name)
        hash = JSON.parse(it.body.read)
      rescue
        hash = {}
      end
      self.new(hash)
    end

    DOC = Hash.new
    DOC.extend(MonitorMixin)
    def self.load(user_id)
      DOC.synchronize do
        unless DOC[user_id]
          last = JSON.parse(Store.get_object("#{user_id}.json")) rescue {}
          DOC[user_id] = self.new(last)
        end
        DOC[user_id]
      end
    end

    def self.sample_data
      DOC.synchronize do
        Store.get_object('5797712.json')
      end
    end

    Item = Struct.new(:seq, :title, :tags)
    class Item
      def id_str
        "R#{seq}"
      end

      def as_json(*)
        {
          "id" => id_str,
          "title" => title,
          "tags" => tags
        }
      end
    
      def to_json(*)
        as_json.to_json
      end

      def tag_classlist
        self.tags.map {|n| "periodic-tag-#{n}"}.join(" ")
      end
    end

    def initialize(hash={})
      super()
      @item = (hash["item"] || []).map {|ary| Item.new(*ary)}
      @checked = (hash["checked"] || {}).map {|k,v| [k, Time.parse(v.to_s)]}.to_h
      @item_seq = (@item.max_by {|x| x.seq}&.seq) || 0
      clean
    end
    attr_reader :item, :checked

    def checked
      clean if @clean_at != Date.today.to_time
      @checked
    end

    def save(user_id)
      Store.put_object("#{user_id}.json", to_h.to_json)
    end

    def to_h
      {
        "item" => @item.map {|it| it.to_a},
        "checked" => @checked
      }
    end

    def period(now = Time.now)
      offset = (5 - 9) % 24 # 5:00 +9 に切り替えたい
      d, h = now.to_i.divmod(24 * 3600)
      if h < offset * 3600
        d -= 1
      end
      Time.at((d * 24 + offset) * 3600)
    end

    def clean
      today = period
      @checked.delete_if {|k, v| v < today} 
      @clean_at = today
    end

    def add_item(title)
      synchronize do
        @item_seq += 1
        it = Item.new(@item_seq, make_uniq_title(title), [])
        @item.unshift(it)
        return it
      end
    end

    def by_seq(seq)
      synchronize do
        @item.find {|it| it.seq == seq}
      end
    end

    def by_id(id_str)
      synchronize do
        @item.find {|it| it.id_str == id_str}
      end
    end

    def check(title, bool)
      if bool
        @checked[title] = Time.now
      else
        @checked.delete(title)
      end
    end

    def set_order(order)
      pp [order.size, @item.size]
      synchronize do
        items = order.uniq.map {|id_str| by_id(id_str)}.compact
        if items.size == @item.size
          @item = items
        end
      end
    end

    def set_title(id_str, title)
      synchronize do
        it = by_id(id_str)
        return nil unless it
        return nil if title == it.title
        if title.empty?
          @item.delete(it)
          return nil
        else
          it.title = make_uniq_title(title)
        end
        return it
      end
    end

    def set_tags(id_str, tags)
      synchronize do
        it = by_id(id_str)
        return nil unless it
        it.tags = tags.map {|x| x.to_i}
        it
      end
    end

    def exist?(title)
      synchronize do
        @item.find {|it| it.title == title}
      end
    end

    def make_uniq_title(title)
      synchronize do
        while @item.find {|it| it.title == title}
          title += '🥷'
        end
        title
      end
    end
  end
end

if __FILE__ == $0
  doc = Periodic::Doc.new
  doc.add_item('hello')
  pp doc.item
  puts doc.item.to_json
end

