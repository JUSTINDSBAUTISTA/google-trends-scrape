class TrendsController < ApplicationController
  def index
    # Display form and existing CSV/ZIP files if necessary
    @current_date_str = Date.today.strftime("%B_%d_%Y")
  end

  def fetch_trends
    uploaded_file = params[:file]
    pick_date = params[:pick_date]  # Capture the pick_date from the form input
    
    if uploaded_file.present?
      begin
        # Handle CSV or XLSX file and parse queries
        queries = if uploaded_file.original_filename.ends_with?('.csv')
          # Handle CSV file
          file_content = File.read(uploaded_file.path).force_encoding("ISO-8859-1").encode("UTF-8", replace: nil)
          csv_data = CSV.parse(file_content, headers: true)
          csv_data.map do |row|
            {
              tag: row['tag'], 
              idType: row['idType'].to_i,  # Ensure idType is an integer
              tagType: row['tagType']
            }
          end
        elsif uploaded_file.original_filename.ends_with?('.xlsx')
          # Handle XLSX file using roo
          xlsx = Roo::Spreadsheet.open(uploaded_file.path)
          sheet = xlsx.sheet(0)
          sheet.parse(headers: true).map do |row|
            {
              tag: row['tag'], 
              idType: row['idType'].to_i,  # Ensure idType is an integer
              tagType: row['tagType']
            }
          end
        else
          raise "Unsupported file type"
        end

        # Distribute queries in random slices and enqueue Sidekiq jobs
        queries.each_slice(rand(6..9)).with_index do |query_batch, index|
          GoogleTrendsScrapingJob.perform_later(query_batch, pick_date, 5)  # Enqueue the job with Sidekiq
          puts "[fetch_trends] Enqueued job #{index + 1} with #{query_batch.size} queries."
        end

        # Set the flash message only after enqueuing jobs
        flash[:notice] = "Google Trends scraping jobs have been queued successfully!"
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
