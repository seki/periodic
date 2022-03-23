require 'json'
require 'monitor'

module Periodic

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

    DOC = {}
    def self.load(user_id)
      unless DOC['user_id']
        pp :doc_load
        it = self.new
        it.add_item("金のなる木を植える")
        it.add_item("住人からレシピ")
        it.add_item("海岸でレシピ")
        it.add_item("金のなる木を植える")
        it.add_item("金のなる木を植える")
        DOC['user_id'] = it
      end
      DOC['user_id']
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
    end

    def initialize(hash=nil)
      super()
      @item_seq = 0
      @item = []
    end
    attr_reader :item

    def add_item(title)
      synchronize do
        @item_seq += 1
        it = Item.new(@item_seq, make_uniq_title(title), 0)
        @item << it
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

    def set_title(id_str, title)
      synchronize do
        it = by_seq(seq)
        return nil unless it
        return nil if title == it.title
        it.title = make_uniq_title(title)
        it
      end
    end

    def set_tags(id_str, tags)
      synchronize do
        it = by_seq(seq)
        return nil unless it
        it.tags = tags
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
