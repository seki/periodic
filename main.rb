require 'webrick'
require 'tofu'
require_relative 'src/app'

port = Integer(ENV['PORT']) rescue 8000
server = WEBrick::HTTPServer.new({
  :Port => port,
  :FancyIndexing => false
})

tofu = Tofu::Bartender.new(Periodic::Session, 'periodic')
server.mount('/app', Tofu::Tofulet, tofu)

if false
  server.mount_proc('/app/auth/twitter/callback') do |req, res|
    _, secret, session_id = Periodic::WaitingOAuth.take([req.query['oauth_token'], nil, nil], 0) rescue nil
    pp [:mount_proc, session_id]

    if session = tofu.instance_variable_get('@bar').fetch(session_id) rescue nil
      session.oauth_callback(req.query['oauth_token'], req.query['oauth_verifier'])
    else
      pp [:session_id, session_id]
    end
    res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, '/')
  end
end

server.mount_proc('/') {|req, res|
  res['Pragma'] = 'no-store'
  res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, '/app')
}

trap(:INT){exit!}
Thread.start do
  while $stdin.gets
    Tofu::reload_erb
  end
end
server.start
