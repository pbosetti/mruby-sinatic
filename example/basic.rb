#!mruby
m = MERB.new
$count = 0

get "/" do
  $count += 1
  m.convert('main.tmpl')
end

get "/options.json" do |r, param|
  Sinatic.options.to_json
end

get "/echo.json" do |r, param|
  {
    r:r,
    query:r.query,
    pairs:query(r), #Gets query string as a hash
    param:param
  }.to_json
end

post "/add" do |r, param|
"
<meta http-equiv=refresh content='2; URL=/'>
通報しますた「#{param['name']}」
"
end

Sinatic.run :host => '0.0.0.0'