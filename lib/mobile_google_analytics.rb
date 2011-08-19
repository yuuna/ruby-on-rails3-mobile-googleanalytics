require 'digest/md5'
require 'net/http'
require 'timeout'
require 'resolv-replace'
require 'jpmobile'
Net::HTTP.version_1_2

#== Example
#
# require 'jpmobile'
# class SampleController < ApplicationController
#  def ga
#    ga = MobileGoogleAnalytics.new(:request => request, :params => params, :cookies => cookies)
#    headers["Cache-Control"] = "private, no-cache, no-cache=Set-Cookie, proxy-revalidate"
#    headers["Pragma"] = "no-cache"
#    headers["Expires"] = "Wed, 17 Sep 1975 21:32:10 GMT"
#    send_data(
#      ga.gif_data,
#      :disposition => "inline",
#      :type => "image/gif"
#    )
#    ga.track_page_view
#  end
class MobileGoogleAnalytics
  VERSION = "4.4sh"
  COOKIE_NAME = "__utmmobile"
  COOKIE_PATH = "/"
  COOKIE_USER_PERSISTENCE = 63072000
  GIF_DATA = [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61,
    0x01, 0x00, 0x01, 0x00, 0x80, 0xff,
    0x00, 0xff, 0xff, 0xff, 0x00, 0x00,
    0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02,
    0x02, 0x44, 0x01, 0x00, 0x3b
  ]

  attr_reader :request, :params, :cookies, :logger

  def initialize(attrs)
    @request = attrs[:request]
    @params = attrs[:params]
    @cookies = attrs[:cookies]
    @logger = Logger.new("#{RAILS_ROOT}/log/mobile_google_analytics.log")
  end

  def get_ip
    return "" unless request.remote_ip

    # Capture the first three octects of the IP address and replace the forth
    # with 0, e.g. 124.455.3.123 becomes 124.455.3.0
    ip = ""
    if request.remote_ip =~ /^([^.]+\.[^.]+\.[^.]+\.).*/
      ip = "#{$1}0"
    end

    return ip
  end

  # Get a random number string
  def get_random_number
    rand(0x7fffffff)
  end

  # Writes the bytes of a 1x1 transparent gif into the response
  def gif_data
    data = GIF_DATA.map{|m| [m].pack('C')}
    data.join("")
  end

  # Generate a visitor id for this hit
  # If there is a visitor id in the cookie, use that, otherwise
  # use the guid if we have one, otherwise use a random number
  def get_visitor_id(guid, account, user_agent, cookie)
    logger.info "guid=#{guid}, account=#{account}, user_agent=#{user_agent}, cookie=#{cookie}"

    # If there is a value in the cookie, don't change it
    if cookie
      return cookie;
    end

    message = "";
    if guid && guid.length > 0
      # Create the visitor id using the guid.
      message = guid + account
    else
      message = user_agent + get_random_number.to_s + get_random_string(30)
    end

    md5_str = Digest::MD5.hexdigest(message.to_s);
    return "0x" + md5_str[0, 16]
  end

  # Track a page view, updates all the cookies and campaign tracker,
  # makes a server side request to Google Analytics and writes the transparent
  # gif byte data to the response.
  def track_page_view
    time_stamp = Time.now
    domain_name = request.host

    # Get the referrer from the utmr parameter, this is the referrer to the
    # page that contains the tracking pixel, not the referrer for tracking
    # pixel.
    document_referer = params[:utmr] || "-"
    document_path = params[:utmp] || ""
    account = params[:utmac] || ""
    user_agent = request.user_agent || ""

    # Try and get visitor cookie from the request.
    cookie = cookies[COOKIE_NAME]
    guid = get_serial_number
    visitor_id = get_visitor_id(guid, account, user_agent, cookie);

    # Always try and add the cookie to the response.
    cookies[COOKIE_NAME] = {
      :value => visitor_id,
      :expiers => Time.now + COOKIE_USER_PERSISTENCE,
      :path => COOKIE_PATH,
      :domain => domain_name
    }

    utm_gif_location= "http://www.google-analytics.com/__utm.gif";

    # Construct the gif hit url.
    url_params = {
      "utmwv" => VERSION,
      "utmn" => get_random_number.to_s,
      "utmhn" => domain_name,
      "utmr" => document_referer.to_s,
      "utmp" => document_path.to_s,
      "utmac" => account.to_s,
      "utmcc" => "__utma=999.999.999.999.999.1;",
      "utmvid" => visitor_id,
      "utmip" => get_ip
    }
    utm_url = utm_gif_location + "?" + url_params.to_query

    response= send_request_to_google_analytics(utm_url);
    result = {:response => response, :request_url => utm_url, :body => nil}
    if response.is_a?(Net::HTTPOK)
      result[:body] = response.body
    else
      logger.error "send request failed!, response=#{response.inspect}, request_url=#{utm_url}"
    end
    return result
  end

  # Make a tracking request to Google Analytics from this server.
  # Copies the headers from the original request to the new one.
  # If request containg utmdebug parameter, exceptions encountered
  # communicating with Google Analytics are thown.
  def send_request_to_google_analytics(utm_url)
    headers = {
     "User-Agent" => request.user_agent.to_s, "Accept-Language" => request.accept_language.to_s
    }
    get_contents(utm_url, :headers => headers)
  end

  # ランダムな文字列を返す
  def get_random_string(length = 8)
    t = Time.now
    srand(t.to_i ^ t.usec ^ Process.pid)
    source = ("a".."z").to_a + (0..9).to_a + ("A".."Z").to_a
    str = ""
    length.times{ str += source[rand(source.size)].to_s }
    return str
  end

  # URLの内容を取得し、レスポンスを返す
  #
  #+url+:: リクエストURL
  #戻り値:: Net::HTTPResponse。エラー時はnil
  def get_contents(url, opts = {})
    opts.reverse_merge! :open_timeout => 1, :read_timeout => 3, :headers => {}
    begin
      uri = URI.parse(url)
      Net::HTTP.start(uri.host, uri.port){|http|
        http.open_timeout = opts[:open_timeout].to_i
        http.read_timeout = opts[:read_timeout].to_i
        return http.get(uri.request_uri, opts[:headers])
      }
    rescue TimeoutError => e
      logger.error "TimeoutError, request_url=#{url}, message=#{e.message}"
    rescue Exception => e
      logger.error "Error, request_url=#{url}, message=#{e.message}"
    end

    nil
  end

  # 携帯の端末番号を返す
  def get_serial_number
    sn = nil
    case request.mobile
    when Jpmobile::Mobile::Docomo
      # iモードID
      if request.env["HTTP_X_DCMGUID"]
        sn = request.env["HTTP_X_DCMGUID"]
      end

      # DoCoMoのエミュレータ
      case request.user_agent
      when 'DoCoMo/2.0 ISIM0505(c100;TB;W24H16)'
        sn = 'ISIM0505'
      when 'DoCoMo/2.0 ISIM0606(c100;TB;W24H16)'
        sn = 'ISIM0606'
      end
    when Jpmobile::Mobile::Au
      # EZ番号
      sn = request.mobile.subno()
    when Jpmobile::Mobile::Softbank
      sn = request.mobile.serial_number()
      if sn == nil
        sn = request.mobile.x_jphone_uid()
      end
    when Jpmobile::Mobile::Vodafone
      sn = request.mobile.serial_number()
      if sn == nil
        sn = request.mobile.x_jphone_uid()
      end
    when Jpmobile::Mobile::Jphone
      sn = request.mobile.serial_number()
      if sn == nil
        sn = request.mobile.x_jphone_uid()
      end
    when Jpmobile::Mobile::Emobile
      # EMnet対応端末ユニークID
      sn = request.mobile.em_uid()
    end

    return sn
  end
end
