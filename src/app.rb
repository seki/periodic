# -*- coding: utf-8 -*-
require 'tofu'
require 'pathname'
require 'pp'
require_relative 'my-oauth'
require_relative 'doc'
require 'json'

module Tofu
  class Tofu
    def normalize_string(str_or_param)
      str ,= str_or_param
      return '' unless str
      str.force_encoding('utf-8').strip
    end
  end
end

module Periodic
  class Session < Tofu::Session
    def initialize(bartender, hint='')
      super

      @tw_screen_name = nil
      @tw_user_id = nil
      @doc = nil

      @base = BaseTofu.new(self)
      @oauth = OAuthTofu.new(self)
      @api = APITofu.new(self)

      @tags = Tags.new
    end
    attr_reader :oauth, :tw_screen_name, :tw_user_id, :tags, :doc
    
    def do_GET(context)
      context.res_header('cache-control', 'no-store')
      super(context)
    end

    def redirect_to(context, path)
      context.res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, 
                               path.to_s)
      context.done
    end

    def lookup_view(context)
      case context.req.path_info
      when '/auth/twitter/callback'
        @oauth
      when /\/api\/.*/
        @api
      else
        @base
      end
    end

    def logout
      @tw_screen_name = nil
      @tw_user_id = nil
      @doc = nil
    end

    def oauth_start(context)
      url = ENV['TW_CALLBACK'] || context.req.request_uri + '/app/auth/twitter/callback'
      pp [:do_login, session_id, url]
      consumer = Periodic::Twitter::consumer
      request_token = consumer.get_request_token(:oauth_callback => url.to_s)
      redirect_to(context, request_token.authorize_url)
    end

    def oauth_callback(token, verifier)
      consumer = Periodic::Twitter::consumer
      request_token = OAuth::RequestToken.new(consumer, token, verifier)
      access_token = consumer.get_access_token(request_token, :oauth_verifier => verifier)
      pp [:oauth_callback, session_id, access_token.params]

      @tw_user_id = access_token.params[:user_id]
      @tw_screen_name = access_token.params[:screen_name]
      @tw_secret = access_token.secret
      @tw_token = access_token.token

      @hint = @tw_user_id

      @doc = Periodic::Doc.load(@tw_user_id)
    rescue
      pp $!
    end

    def login_local(data)
      hash = JSON.parse(data) rescue {}
      @doc = Periodic::Doc.new(hash)
      @hint = @tw_user_id = 'local'
    end

    def local?
      @tw_user_id == 'local'
    end
  end

  class Tags
    Default = %w(bi-sun bi-moon-stars bi-nintendo-switch bi-door-open bi-piggy-bank bi-chat-text).map {
      |x| %Q+<i class="bi #{x}"></i>+
    }
    def to_a
      Default
    end
  end

  class OAuthTofu < Tofu::Tofu
    @erb_method = []
    def to_html(context)
      @session.oauth_callback(context.req.query['oauth_token'], context.req.query['oauth_verifier'])
      @session.redirect_to(context, '/')
    end

    def tofu_id
      'oauth'
    end
  end

  class APITofu < Tofu::Tofu
    @erb_method = []

    def to_html(context)

      result = {"status" => "ok"}
      body = JSON.parse(context.req.body)
      
      if body['op'] == 'login_local'
        data = body['data'] || Doc.sample_data
        @session.login_local(data)
      elsif @session.doc
        case body['op']
        when 'add'
          pp @session.doc.add_item(body['title'])
          pp @session.doc
        when 'update'
          new_one = @session.doc.set_title(body['id'], body['title'])
          if new_one
            result["title"] = new_one.title
          end
        when 'check'
          pp @session.doc.check(body['title'], body['value'])
          pp @session.doc.checked
        when 'tags'
          pp @session.doc.set_tags(body['id'], body['tags'])
        when 'order'
          pp @session.doc.set_order(body['order'])
        end
        if @session.local?
          result['data'] = @session.doc.to_h.to_json
        else
          @session.doc.save(@session.tw_user_id)
        end
      else
        result = {"status" => "login"}
      end
    
      context.res_header('content-type', 'application/json')
      context.res_body(result.to_json)
      context.done
    end

    def tofu_id
      'api'
    end
  end

  class BaseTofu < Tofu::Tofu
    set_erb(__dir__ + '/base.html')

    def initialize(session)
      super(session)
      @list = ListTofu.new(session)
      @edit = EditTofu.new(session)
      @login = LoginTofu.new(session)
    end

    def tofu_id
      'base'
    end

    def pathname(context)
      script_name = context.req_script_name
      script_name = '/' if script_name.empty?
      Pathname.new(script_name)
    end

    def do_login(context, params)
      @session.oauth_start(context)
    end

    def do_logout(context, params)
      @session.logout
      @session.redirect_to(context, '/app/')
    end
  end

  class ListTofu < Tofu::Tofu
    set_erb(__dir__ + '/list.html')

    def list(context)
      doc = @session.doc
      return [] unless doc
      doc.item.map {|x| [x, doc.checked.include?(x.title)]}
    end
  end

  class LoginTofu < Tofu::Tofu
    set_erb(__dir__ + '/login.html')

    def tofu_id
      'login'
    end

    def do_login(context, params)
      @session.oauth_start(context)
    end

    def do_login_local(context, params)
      
    end
  end

  class EditTofu < Tofu::Tofu
    set_erb(__dir__ + '/edit.html')

    def list(context)
      doc = @session.doc
      return [] unless doc
      doc.item
    end
  end
end