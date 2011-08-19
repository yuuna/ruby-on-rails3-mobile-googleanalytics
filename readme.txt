ruby on rails３にて携帯サイトを作った際に、googleアナリティック解析ライブラリー

１、libにgoogleアナリティックを設置

２、application_helperに下記を追加
  # Copyright 2009 Google Inc. All Rights Reserved.
  def google_analytics_tag
    tracking_code = "MO-24625346-1" # トラッキングコード

    ga_account = tracking_code
    url_params = {
      "utmac" => ga_account,
      "utmn" => rand(0x7fffffff).to_s,
      "utmr" => request.referer || "-",
      "utmp" => request.request_uri
    }
    tmp = []
    url_params.keys.sort.each{|key|
       tmp << "#{key}=" + CGI.escape(url_params[key])
    }
    tmp << "guid=ON"
    image_url = url_for(:controller => :application, :action => :ga) + "?" + tmp.join("&amp;")

    "<img border=\"0\" height=\"1\" src=\"#{image_url}\" width=\"1\" />"
  end


３、applicaiton_controllerに下記を追加
 #
 # googleAnalyticsを活用するためのメソッド
 #
 def ga
   ga = MobileGoogleAnalytics.new(:request => request, :params => params, :cookies => cookies)
   headers["Cache-Control"] = "private, no-cache, no-cache=Set-Cookie, proxy-revalidate"
   headers["Pragma"] = "no-cache"
   headers["Expires"] = "Wed, 17 Sep 1975 21:32:10 GMT"
   send_data(
   ga.gif_data,
     :disposition => "inline",
     :type => "image/gif"
    )
   ga.track_page_view
 end

４、rootingに下記を追加
  ##
  # google_analytics
  match "ga", :to => "application#ga"

5、Viewに下記を追加
<% if RAILS_ENV == "production" %>
  <!-- begin google_analytics -->
  <%= raw google_analytics_tag %>
  <!-- end google_analytics -->
<% end %>


以上で設置できる。
