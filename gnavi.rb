# encoding: utf-8
require 'net/http'
require 'kconv'
require 'nokogiri'
require 'csv'

# 第一引数が対象年(YYYY)
# 第二引数が対象月(MM)
# 認証情報 ['店名', 'id', 'password']
year = ARGV[0]
month = ARGV[1]
auth = []

###################
# 関数群
###################

# ログインを実行し、cookie情報を返却
def login(id, passwd) 
	# ログイン実施、セッション確立
	con = Net::HTTP.new 'pro.gnavi.co.jp'
	uri = '/bp/auth/login.php?id=' + id + '&pass=' + passwd + '&logintype=1'
	res = con.get uri

	# クッキー一覧取得
	cookies = {}
	if res.key? 'set-cookie'           # set-cookieフィールドがある?
	  res.get_fields('set-cookie').each { |c|
	    c =~ /(.+?)=(.+?)[;\s$]/
	    cookies[$1] = $2 if $1
	  }
	end

	# リクエストヘッダにクッキー追加
	h = {}
	if cookies
	  h['cookie'] = cookies.map { |k, v|
	    "#{k}=#{v}"
	  }.join('; ')
	end

	return h
end


# 実際のデータ取得を実施
def scrape(h, year, month)
	# 取得データ格納先
	dates = []
	prices = []

	# データ取得
	con = Net::HTTP.new 'manage.gnavi.co.jp'
	uri = '/newtouch/receipt/statement/touch_m.php?year=' + year + '&month=' + month
	res = con.get uri, h
	root = Nokogiri::HTML res.body.toutf8

	# テーブル取得
	if root && root.xpath('//table')[3] then
		# テーブル要素取得
		root.xpath('//table')[3].xpath('.//tr').each { |i|
			# 日付部取得
			if i.xpath('.//td')[0] && i.xpath('.//td')[0].xpath('.//a') then
				raw_date = i.xpath('.//td')[0].xpath('.//a').inner_text
				dates << raw_date.gsub(/\([月火水木金土日]\)/, '')
			end

			# 決済額取得
			if i.xpath('.//td')[3] then
				raw_price = i.xpath('.//td')[2].inner_text
				prices << raw_price.gsub(/["\-,]/, '')
			end
		}

		# 総計挿入
		dates << "中旬合計"
		prices << prices[0..14].inject { |sum, i| sum.to_i + i.to_i }

		dates << "月末合計"
		prices << prices[15..-2].inject { |sum, i| sum.to_i + i.to_i }
	end

	return {'dates' => dates, 'prices' => prices}
end


# 実行メソッド
def exec(id, passwd, year, month)
	h = login(id, passwd)
	return scrape(h, year, month)
end


###################
# メイン処理
###################

# CSV出力準備
path = ARGV.shift
file_name = year + month + '.csv'
new_csv = File.join(File.dirname(path), file_name)

# CSV書き込み開始
CSV.open(new_csv, "wb") do |csv|
	is_first = true
	auth.each{|shop|
		# コンソール出力
		puts "getting " + shop[0] + "..."

		# 変数準備
		shop_name = shop[0].encode("Shift_JIS", :undef => :replace, :replace => "")
		id = shop[1]
		passwd = shop[2]

		# データ取得
		res = exec(shop[1], shop[2], year, month)

		# 初回のみヘッダー出力
		if is_first then
			is_first = false

			row = [''].concat(res['dates'])
			encoded_row = []
			row.each { |item| encoded_row << item.strip.encode("Shift_JIS", :undef => :replace, :replace => "")}
			csv << encoded_row
		end

		# 店舗情報出力
		row = [shop_name].concat(res['prices'])
		csv << row
	}
end
