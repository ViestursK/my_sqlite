require 'csv'

class MySqliteRequest
  def initialize
    # Initialize variables to hold table name, column data, conditions, and more
    @table_name = nil
    @select_columns = []
    @where_conditions = []
    @join_data = nil
    @order_params = nil
    @insert_data = nil
    @update_data = nil
    @delete_flag = false
    @debug_mode = false # Set to true to see debugging output
  end

  # Set the table name to query and validate if the file exists
  def from(table_name)
    # Add .csv extension if not present
    table_name = "#{table_name}.csv" unless table_name.end_with?('.csv')
    
    if !File.exist?(table_name)
      raise "Error: Table '#{table_name}' not found."
    end
    @table_name = table_name
    self
  end

  # Enable debug mode for verbose output
  def debug(enable = true)
    @debug_mode = enable
    self
  end

  # Specify which columns to select (can handle multiple columns as an array)
  def select(columns)
    columns = [columns].flatten
    @select_columns = columns
    self
  end

  # Add a WHERE condition to filter results based on column criteria
  def where(column_name, criteria)
    @where_conditions << { column: column_name, criteria: criteria }
    self
  end

  # Define a JOIN operation between two tables based on specified columns
  def join(column_on_db_a, filename_db_b, column_on_db_b)
    # Add .csv extension if not present
    filename_db_b = "#{filename_db_b}.csv" unless filename_db_b.end_with?('.csv')
    
    if !File.exist?(filename_db_b)
      raise "Error: Table '#{filename_db_b}' not found for join."
    end
    @join_data = { db_a_column: column_on_db_a, db_b_file: filename_db_b, db_b_column: column_on_db_b }
    self
  end

  # Define the ordering of results (either :asc or :desc)
  def order(order, column_name)
    unless %i[asc desc].include?(order)
      raise "Error: Invalid order '#{order}', must be :asc or :desc."
    end
    @order_params = { order: order, column: column_name }
    self
  end

  # Start the INSERT operation and specify the table to insert into
  def insert(table_name)
    from(table_name)
    self
  end

  # Provide the values to be inserted into the table (must be a non-empty hash)
  def values(data)
    if data.empty? || !data.is_a?(Hash)
      raise "Error: Values must be provided as a non-empty hash."
    end
    @insert_data = data
    self
  end

  # Start the UPDATE operation and specify the table to update
  def update(table_name)
    from(table_name)
    self
  end

  # Provide the new values to update in the table (must be a non-empty hash)
  def set(data)
    if data.empty? || !data.is_a?(Hash)
      raise "Error: Update data must be provided as a non-empty hash."
    end
    @update_data = data
    self
  end

  # Mark the operation as a DELETE operation
  def delete
    @delete_flag = true
    self
  end

  # Run the query based on the type of operation (select, insert, update, delete)
  def run
    raise "Error: No table specified." unless @table_name
    if @delete_flag
      execute_delete
    elsif @insert_data
      execute_insert
    elsif @update_data
      execute_update
    else
      execute_select
    end
  rescue StandardError => e
    puts e.message
    nil
  end

  private

  # Execute a SELECT query, applying where conditions, joins, and orders
  def execute_select
    data = read_table
    return [] if data.empty?
    
    debug_log("Initial data rows: #{data.length}")
    
    data = apply_where_conditions(data)
    return [] if data.empty?
    debug_log("After WHERE conditions: #{data.length} rows")
    
    data = apply_join(data) if @join_data
    return [] if data.empty?
    debug_log("After JOIN: #{data.length} rows") if @join_data
    
    data = apply_order(data) if @order_params
    debug_log("After ORDER: #{data.length} rows") if @order_params
  
    if @select_columns.any?
      # Safe check for data.first existence
      if data.empty?
        return []
      end
      
      debug_log("Available columns in data: #{data.first.keys}")
      
      # Handle wildcard * selection
      if @select_columns.include?('*')
        # Return all columns, no filtering needed
        debug_log("Wildcard selection, returning all columns")
      else
        # Ensure all selected columns exist in the data
        validate_columns(@select_columns, data.first.keys)
        data.map! { |row| row.slice(*@select_columns) }
      end
    end
  
    debug_log("Final data rows: #{data.length}")
    data
  end

  # Execute an INSERT query, adding a new row to the table
  def execute_insert
    headers = read_headers
    validate_columns(@insert_data.keys, headers)
  
    # Ensure ID is present
    unless @insert_data.key?('id')
      last_id = CSV.read(@table_name, headers: true).map { |row| row['id'].to_i }.max || 0
      @insert_data['id'] = (last_id + 1).to_s
    end
  
    CSV.open(@table_name, 'a') { |csv| csv << headers.map { |h| @insert_data[h] } }
    debug_log("Row inserted successfully.")
    { status: "success", message: "Row inserted successfully." }
  end

  # Execute an UPDATE query, modifying existing rows based on the where conditions
  def execute_update
    raise "Error: No update data provided." if @update_data.nil? || @update_data.empty?
  
    # Read the table as CSV, headers as symbols
    data = CSV.table(@table_name)
    
    # Get the actual headers from the CSV file
    available_columns = data.headers.map(&:to_s)
    debug_log("Available columns: #{available_columns}")
    
    # Validate that update columns exist in the table
    validate_columns(@update_data.keys, available_columns)
  
    updated_rows = 0
    data.each do |row|
      if matches_conditions?(row)
        @update_data.each do |key, value| 
          row[key.to_sym] = value 
        end
        updated_rows += 1
      end
    end
  
    if updated_rows.zero?
      puts "Warning: No rows matched the update criteria."
      return { status: "warning", message: "No rows matched the update criteria." }
    end
  
    File.write(@table_name, data.to_csv)
    debug_log("#{updated_rows} rows updated.")
    { status: "success", message: "#{updated_rows} rows updated." }
  end 

  # Execute a DELETE query, removing rows based on the where conditions
  def execute_delete
    begin
      data = CSV.table(@table_name)
      initial_size = data.size
      deleted_count = 0

      # Create a new table without the rows to delete
      if @where_conditions.empty?
        # Delete all rows if no conditions specified
        data.delete_if { |_| true }
        deleted_count = initial_size
      else
        # Use a standard array to track which rows to delete
        rows_to_delete = []
        
        data.each.with_index do |row, idx|
          if matches_conditions?(row)
            rows_to_delete << idx
            deleted_count += 1
          end
        end
        
        # Delete rows in reverse order to avoid index shifting problems
        rows_to_delete.reverse_each do |idx|
          data.delete(idx)
        end
      end

      # Write the updated data back to the file
      File.write(@table_name, data.to_csv)
      
      debug_log("#{deleted_count} rows deleted.")
      
      if deleted_count == 0
        puts "Warning: No rows matched the delete criteria."
        return { status: "warning", message: "No rows matched the delete criteria." }
      else
        return { status: "success", message: "#{deleted_count} rows deleted." }
      end
    rescue StandardError => e
      puts "Error during DELETE operation: #{e.message}"
      return { status: "error", message: e.message }
    end
  end

  # Check if a row matches all WHERE conditions
  def matches_conditions?(row)
    @where_conditions.all? do |cond|
      row_value = row[cond[:column].to_sym]
      # Simple string comparison for now, can be extended for more complex operators
      row_value.to_s == cond[:criteria].to_s
    end
  end

  # Apply WHERE conditions to the data (filter rows based on conditions)
  def apply_where_conditions(data)
    return data if @where_conditions.empty?
    return [] if data.empty?

    @where_conditions.each do |cond|
      if data.first && !data.first.keys.include?(cond[:column])
        puts "Error: Column '#{cond[:column]}' not found in the table."
        return []
      end
      
      # Filter the data
      data = data.select { |row| row[cond[:column]] == cond[:criteria] }
      
      # If no rows match, return empty array early
      return [] if data.empty?
    end
    data
  end

  # Apply a JOIN operation on the data based on the join data provided
  def apply_join(data)
    return [] if data.empty?
    
    begin
      join_data = CSV.read(@join_data[:db_b_file], headers: true).map(&:to_h)
      
      if join_data.empty?
        puts "Error: Table '#{@join_data[:db_b_file]}' is empty."
        return []
      end
    
      db_a_column = @join_data[:db_a_column] # e.g., 'name'
      db_b_column = @join_data[:db_b_column] # e.g., 'Player'
    
      unless data.first.keys.include?(db_a_column)
        puts "Error: Join column '#{db_a_column}' not found in first table."
        return []
      end
      
      unless join_data.first.keys.include?(db_b_column)
        puts "Error: Join column '#{db_b_column}' not found in second table."
        return []
      end
    
      # Perform the join - using a more explicit approach for debugging
      joined_data = []
      
      data.each do |row_a|
        value_to_match = row_a[db_a_column]
        matching_rows = join_data.select { |row_b| row_b[db_b_column] == value_to_match }
        
        if matching_rows.any?
          matching_rows.each do |row_b|
            joined_row = row_a.dup
            row_b.each do |k, v|
              joined_row[k] = v unless k == db_b_column && joined_row.key?(k)
            end
            joined_data << joined_row
          end
        else
          # For INNER JOIN behavior (default), don't add non-matching rows
          # For LEFT JOIN, you would uncomment: joined_data << row_a.dup
        end
      end
    
      # Debug: Print the join results
      if @debug_mode
        debug_log("Join from #{data.length} rows in table A with #{join_data.length} rows in table B")
        debug_log("Resulted in #{joined_data.length} joined rows")
        if joined_data.any?
          debug_log("First joined row: #{joined_data.first}")
          debug_log("Columns in joined data: #{joined_data.first.keys}")
        end
      end
      
      return joined_data
    rescue StandardError => e
      puts "Error during JOIN operation: #{e.message}"
      return []
    end
  end

  # Apply the ORDER BY operation to the data based on the specified column and order
  def apply_order(data)
    return data if data.empty?
    validate_columns([@order_params[:column]], data.first.keys)

    # Store original height values before sorting them numerically
    if @order_params[:column] == 'height'
      data.each do |row|
        row['original_height'] = row['height'] # Save original height value
        row['height'] = height_to_numeric(row['height']) # Convert to numeric for sorting
      end
    end

    # Sort the data based on the specified column and order
    data.sort_by! { |row| row[@order_params[:column]] }
    data.reverse! if @order_params[:order] == :desc

    # Convert height back to its original format after sorting
    if @order_params[:column] == 'height'
      data.each do |row|
        row['height'] = row['original_height']
        row.delete('original_height')
      end
    end

    data
  end

  # Helper method to convert height (e.g., '6-3') to inches for sorting
  def height_to_numeric(height)
    if height.is_a?(String) && height.include?('-')
      feet, inches = height.split('-').map(&:to_i)
      return (feet * 12) + inches
    else
      return height.to_i
    end
  end

  # Read the table from the CSV file and return the rows as an array of hashes
  def read_table
    data = CSV.read(@table_name, headers: true)
    raise "Error: Table '#{@table_name}' is empty." if data.empty?
  
    data.map(&:to_h)
  end

  # Read the headers of the CSV file
  def read_headers
    CSV.open(@table_name, 'r') { |csv| csv.first }
  end

  # Validate if the provided columns exist in the table
  def validate_columns(columns, available_columns)
    # Convert all column names to strings and remove nil keys
    columns = columns.map(&:to_s)
    available_columns = available_columns.compact.map(&:to_s) # Remove nil keys
  
    # Skip validation for wildcard
    return true if columns.include?('*')
    
    missing_columns = columns - available_columns
    unless missing_columns.empty?
      raise "Error: Columns not found in table: #{missing_columns.join(', ')}."
    end
  end

  # Print debug information if debug mode is enabled
  def debug_log(message)
    puts "DEBUG: #{message}" if @debug_mode
  end
end