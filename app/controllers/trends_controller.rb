class TrendsController < ApplicationController
  def index
    # Display form and existing CSV/ZIP files if necessary
  end

  def fetch_trends
    uploaded_file = params[:file]
    pick_date = params[:pick_date]  # Capture the pick_date from the form input
  
    if uploaded_file.present?
      begin
        queries = if uploaded_file.original_filename.ends_with?('.csv')
          # Handle CSV file
          file_content = File.read(uploaded_file.path).force_encoding("ISO-8859-1").encode("UTF-8", replace: nil)
          csv_data = CSV.parse(file_content, headers: true)
          csv_data.map { |row| { tag: row['tag'], idType: row['idType'], tagType: row['tagType'] } }
        elsif uploaded_file.original_filename.ends_with?('.xlsx')
          # Handle XLSX file using roo
          xlsx = Roo::Spreadsheet.open(uploaded_file.path)
          sheet = xlsx.sheet(0)
          sheet.parse(headers: true).map { |row| { tag: row['tag'], idType: row['idType'], tagType: row['tagType'] } }
        else
          raise "Unsupported file type"
        end
  
        # Proceed with scraping
        scraper = GoogleTrendsScraper.new
        scraper.fetch_and_export_trends(queries, pick_date)
  
        flash[:notice] = "Google Trends data fetched successfully!"
      rescue CSV::MalformedCSVError => e
        flash[:alert] = "CSV file is invalid: #{e.message}"
      rescue => e
        flash[:alert] = "An error occurred: #{e.message}"
      ensure
        redirect_to trends_path
      end
    else
      flash[:alert] = "Please upload a valid CSV or XLSX file."
      redirect_to trends_path
    end
  end
  
  def download_zip
    zip_file = Rails.root.join('public', 'trends_data.zip')
    if File.exist?(zip_file)
      send_file(zip_file, type: 'application/zip', filename: 'trends_data.zip', disposition: 'attachment')
    else
      flash[:alert] = "ZIP file not found."
      redirect_to trends_path
    end
  end
end
