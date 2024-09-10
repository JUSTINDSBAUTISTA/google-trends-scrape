require 'httparty'
require 'nokogiri'
require 'csv'

class GoogleTrendsScraper
  def initialize(query)
    @query = query
  end

  def fetch_trends_page
    url = "https://trends.google.ca/trends/explore?q=#{@query}&date=now%201-d&geo=CA&hl=en-GB"

    begin
      response = HTTParty.get(url)
      puts "Response Code: #{response.code}"

      if response.code == 200
        html = response.body
        puts "Fetched HTML successfully"
      else
        puts "Failed to fetch HTML. Response code: #{response.code}"
        html = ""
      end
    rescue StandardError => e
      puts "Error fetching HTML: #{e.message}"
      html = ""
    end

    sleep(10)  # Wait for 10 seconds
    html
  end

  def parse_trends_page(html)
    doc = Nokogiri::HTML.parse(html)
    data = doc.css('a.progress-label').map do |link|
      {
        id_tag: link.css('.label-text').text.strip,
        tag: link.css('span[ng-bind="bidiText"]').text.strip,
        tag_type: link.css('.label-line-number').text.strip,
        articles: link.css('.rising-value').text.strip,
        href: link['href']
      }
    end

    puts "Parsed Data:"
    puts data.inspect
    data
  end

  def write_to_csv(data)
    CSV.open("trends_data.csv", "wb") do |csv|
      # Adding a header row
      csv << ["idTag", "tag", "idType", "articles", "URL"]
      data.each do |entry|
        csv << [entry[:id_tag], entry[:tag], entry[:tag_type], entry[:articles], "https://trends.google.ca#{entry[:href]}"]
      end
    end
    puts "CSV file written successfully." # Debugging line
  end

  def fetch_and_export_trends
    html = fetch_trends_page
    data = parse_trends_page(html)
    write_to_csv(data)
  end
end
