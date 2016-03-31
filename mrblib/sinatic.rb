module Sinatic
  HTTP_STATUS = {
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    301 => 'Moved Permanently',
    400 => 'Bar Request',
    403 => 'Forbidden',
    404 => 'Not Found',
    500 => 'Internal Server Error'
  }
  HTTP_STATUS.default = 'Internal Server Error'
  
  TYPE_FOR_EXT = {
    'txt'  => 'text/txt',
    'html' => 'text/html' ,
    'css'  => 'text/css',
    'js'   => 'text/javascript',
    'yaml' => 'application/x-yaml',
    'json' => 'application/json'
  }
  TYPE_FOR_EXT.default = 'application/octet-stream'
  
  @content_type = nil
  @options = {
    host:'127.0.0.1',
    port: 8888,
    public: 'public'
  }
  @routes = {'GET' => [], 'POST' => [], 'DELETE' => []}
  @request = ''
  @shutdown = false
  
  def self.options
    @options
  end
  
  def self.route(method, path, opts, &block)
    @routes[method] << [path, opts, block]
  end
  
  def self.content_type
    @content_type
  end
  
  def self.content_type=(type)
    @content_type = type
  end
  
  def self.set(key, value)
    @options[key] = value
  end
  
  def self.response_header(code, type, content)
    lines = []
    lines.push "HTTP/1.0 #{code} #{HTTP_STATUS[code]}"
    if code == 200
      lines.push "Content-Type: #{type}"
    end
    lines.push "Content-Length: #{content.size}"
    lines.push ""
    lines.push ""
    return code, lines.join("\r\n") + content
  end
  
  def self.do(r)
    route = @routes[r.method].select {|path|
      if path[0].class == String
        r.path == path[0]
      else
        r.path =~ /#{path[0]}/
      end
    }
    
    code = 200
    # There is a route for dealing with r
    if route.size > 0 then
      param = {}
      if r.headers['Content-Type'] == 'application/x-www-form-urlencoded'
        r.body.split('&').each do |x|
          tokens = x.split('=', 2)
          if tokens && tokens.size == 2
            param[tokens[0]] = HTTP::URL::decode(tokens[1])
          end
        end
      end
      parts = r.path.split(".")
      if parts.size > 1 then
        @content_type = TYPE_FOR_EXT[parts.last]
      else
        @content_type = 'text/html; charset=utf-8'
      end
      bb = route[0][2].call(r, param)
      if bb.class == Array
        code, bb = bb
      end
    
    # no routes installed, serve a static asset
    elsif r.method == 'GET' && r.path then
      f = nil
      begin
        file = r.path + (r.path[-1] == '/' ? 'index.html' : '')
        ext = file.split(".")[-1]
        @content_type = TYPE_FOR_EXT[ext]
        f = UV::FS::open("#{@options[:public]}#{file}", UV::FS::O_RDONLY, UV::FS::S_IREAD)
        bb = ''
        while (read = f.read(4096, bb.size)).size > 0
          bb += read
        end
      rescue => ex
        # 404
        code = 404
        bb = HTTP_STATUS[code]
        puts "> [#{r.path}=>#{code}] Sinatic Error on request #{r.headers}:\n#{bb}"
      ensure
        f.close if f
      end
    end
    return response_header(code, @content_type, bb)
  end
  
  def self.shutdown?
    @shutdown
  end
  
  def self.shutdown
    @shutdown = true
  end
  
  def self.run(options = {})
    s = UV::TCP.new
    @options.merge!(options)
    
    s.bind(UV::ip4_addr(@options[:host], @options[:port]))
    s.listen(2000) do |x|
      return if x != 0 or s == nil
      begin
        c = s.accept
        c.data = ''
      rescue
        return
      end
      c.read_start do |b|
        begin
          next unless b
          c.data += b
          i = c.data.index("\r\n\r\n")
          if i != nil && i >= 0
            r = HTTP::Parser.new.parse_request(c.data)
            r.body = c.data.slice(i + 4, c.data.size - i - 4)
            if !r.headers['Content-Length'] || r.headers['Content-Length'].to_i == r.body.size
              code, bb = ::Sinatic.do(r)
              @content_type = nil
              if !r.headers['Connection'] || r.headers['Connection'].upcase != 'KEEP-ALIVE'
                c.write(bb) do |x|
                  c.close if c && !c.closing?
                  c = nil
                end
              else
                c.write(bb)
                c.data = ''
              end
            end
          end
        rescue => ex
          msg = "Internal Server Error\nRuby message: [#{ex.class}] #{ex.message}"
          code, err = response_header(500, nil, msg)
          puts "> [#{code}] Sinatic Error on request #{r.headers}:\n#{msg}"
          c.write(err) do |x|
            c.close if c && !c.closing?
            c = nil
          end
        end
      end
    end

    t = UV::Timer.new
    t.data = s
    t.start(3000, 3000) do |x|
      if Sinatic.shutdown?
        t.data.close
        t.data = nil
        t.close
        t = nil
      end
      UV::gc
    end

    UV::run
  end
end

module Kernel
  def get(path, opts={}, &block)
    ::Sinatic.route 'GET', path, opts, &block
  end
  
  def post(path, opts={}, &block)
    ::Sinatic.route 'POST', path, opts, &block
  end
  
  def delete(path, opts={}, &block)
    ::Sinatic.route 'DELETE', path, opts, &block
  end
  
  def content_type(type)
    ::Sinatic.content_type = type
  end
  
  def set(key, value)
    ::Sinatic.set key, value
  end
  
  def query(r)
    return "" unless r.query
    pairs = r.query.split('&')
    keys = []
    values = []
    pairs.each {|e| k, v = e.split('='); keys << k; values << v}
    return keys.zip(values).to_h
  end
end

# vim: set fdm=marker: