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
  end

  # Set the table name to query and validate if the file exists
  def from(table_name)
    if !File.exist?(table_name)
      raise "Error: Table '#{table_name}' not found."
    end
    @table_name = table_name
    self
  end

  # Specify which columns to select (can handle multiple columns as an array)
  def select(columns)
    @select_columns = [columns].flatten
    self
  end

  # Add a WHERE condition to filter results based on column criteria
  def where(column_name, criteria)
    @where_conditions << { column: column_name, criteria: criteria }
    self
  end

  # Define a JOIN operation between two tables based on specified columns
  def join(column_on_db_a, filename_db_b, column_on_db_b)
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
  end

  private

  # Execute a SELECT query, applying where conditions, joins, and orders
  def execute_select
    data = read_table
    data = apply_where_conditions(data)
    data = apply_join(data) if @join_data
    data = apply_order(data) if @order_params
  
    if @select_columns.any?
      # Debugging: Print available columns in the data
      puts "Available columns in data: #{data.first.keys}"
  
      # Ensure all selected columns exist in the data
      validate_columns(@select_columns, data.first.keys)
      data.map! { |row| row.slice(*@select_columns) }
    end
  
    puts "Final data: #{data}" # Debugging: Print the final data
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
    puts "Row inserted successfully."
  end

  # Execute an UPDATE query, modifying existing rows based on the where conditions
  def execute_update
    raise "Error: No update data provided." if @update_data.nil? || @update_data.empty?
  
    data = CSV.table(@table_name)
    validate_columns(@update_data.keys, data.headers.map(&:to_s))
  
    updated_rows = 0
    data.each do |row|
      if @where_conditions.all? { |cond| row[cond[:column].to_sym] == cond[:criteria] }
        @update_data.each { |key, value| row[key.to_sym] = value }
        updated_rows += 1
      end
    end
  
    raise "Error: No rows matched the update criteria." if updated_rows.zero?
  
    File.write(@table_name, data.to_csv)
    puts "#{updated_rows} rows updated."
  end 

  # Execute a DELETE query, removing rows based on the where conditions
  def execute_delete
    data = CSV.table(@table_name)
    initial_size = data.size

    data.delete_if do |row|
      @where_conditions.all? { |cond| row[cond[:column].to_sym] == cond[:criteria] }
    end

    File.write(@table_name, data.to_csv)
    puts "#{initial_size - data.size} rows deleted."
  end

  # Apply WHERE conditions to the data (filter rows based on conditions)
  def apply_where_conditions(data)
    return data if @where_conditions.empty?

  @where_conditions.each do |cond|
    unless data.first.keys.include?(cond[:column])
      raise "Error: Column '#{cond[:column]}' not found in the table."
  end
    data.select! { |row| row[cond[:column]] == cond[:criteria] }
  end
    data
  end

  def apply_where_conditions(data)
    return data if @where_conditions.empty?

    @where_conditions.each do |cond|
      unless data.first.keys.include?(cond[:column])
        raise "Error: Column '#{cond[:column]}' not found in the table."
      end
      data.select! { |row| row[cond[:column]] == cond[:criteria] }
    end
    data
  end

  # Apply a JOIN operation on the data based on the join data provided
  def apply_join(data)
    join_data = CSV.read(@join_data[:db_b_file], headers: true).map(&:to_h)
    raise "Error: Table '#{@join_data[:db_b_file]}' is empty." if join_data.empty?
  
    db_a_column = @join_data[:db_a_column] # e.g., 'name'
    db_b_column = @join_data[:db_b_column] # e.g., 'Player'
  
    unless data.first.keys.include?(db_a_column) && join_data.first.keys.include?(db_b_column)
      raise "Error: Join column not found in one or both tables."
    end
  
    # Perform the join
    joined_data = data.flat_map do |row|
      join_data.select { |join_row| row[db_a_column] == join_row[db_b_column] }
               .map { |join_row| row.merge(join_row) }
    end
  
    # Debugging: Print the first joined row to verify columns
    if joined_data.any?
      puts "First joined row: #{joined_data.first}"
      puts "Columns in joined data: #{joined_data.first.keys}"
    end  
    joined_data
  end

  # Apply the ORDER BY operation to the data based on the specified column and order
  def apply_order(data)
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
    data.each do |row|
      row['height'] = numeric_to_height(row['height'])
    end

    data
  end

  # Helper method to convert numeric height back to feet-inches format
  def numeric_to_height(height_in_inches)
    feet = height_in_inches / 12
    inches = height_in_inches % 12
    "#{feet}-#{inches}"
  end

  # Helper method to convert height (e.g., '6-3') to inches
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
  
    missing_columns = columns - available_columns
    unless missing_columns.empty?
      raise "Error: Columns not found in table: #{missing_columns.join(', ')}."
    end
  end
end

# __________
# TESTS 

# def test_insert
#     puts "Test 1: Insert a new row"
#     MySqliteRequest.new.insert('nba_player_data_copy.csv').values({
#       'name' => 'John Doe',
#       'year_start' => '2024',
#       'year_end' => '2026',
#       'position' => 'G',
#       'height' => '6-5',
#       'weight' => '210',
#       'birth_date' => 'March 14, 2000',
#       'college' => 'Duke University'
#     }).run
#     puts "Inserted new player: John Doe\n\n"
#   end
  
#   def test_select
#     puts "Test 2: Select rows based on conditions"
#     result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                               .select(['name', 'position', 'college'])
#                               .where('college', 'Duke University')
#                               .run
#     puts "Selected data from Duke University: #{result.inspect}\n\n"
#   end
  
#   def test_update
#     puts "Test 3: Update a player's position"
#     MySqliteRequest.new.from('nba_player_data_copy.csv')
#       .update('nba_player_data_copy.csv')
#       .where('name', 'John Doe')
#       .set({ 'position' => 'PG' })
#       .run
  
#     # Check the updated player
#     result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                               .select(['name', 'position'])
#                               .where('name', 'John Doe')
#                               .run
#     puts "Updated player: #{result.inspect}\n\n"
#   end
  
#   def test_delete
#     puts "Test 4: Delete a player"
#     MySqliteRequest.new.from('nba_player_data_copy.csv')
#       .delete
#       .where('name', 'John Doe')
#       .run
#     puts "Deleted player: John Doe\n\n"
#   end
  
# def test_join
#   puts "Test 5: Join two tables"
#   result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                             .join('name', 'nba_players.csv', 'Player')
#                             .select(['name', 'college'])
#                             .where('college', 'Duke University')
#                             .run
#   puts "Joined data: #{result.inspect}\n\n"
# end
    
#   def test_order
#     puts "Test 6: Apply ORDER BY (height desc)"
#     result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                               .select(['name', 'height'])
#                               .order(:asc, 'height')
#                               .run
#     puts "Ordered by height (desc): #{result.inspect}\n\n"
#   end
  
#   def test_multiple_operations
#     puts "Test 7: Combined operations (Insert, Select, Update, Delete)"
  
#     # Insert new player
#     MySqliteRequest.new.insert('nba_player_data_copy.csv').values({
#       'name' => 'Test Player',
#       'year_start' => '2024',
#       'year_end' => '2025',
#       'position' => 'G',
#       'height' => '6-3',
#       'weight' => '190',
#       'birth_date' => 'January 1, 2000',
#       'college' => 'Test University'
#     }).run
#     puts "Inserted new player: Test Player\n"
  
#     # Select inserted player
#     result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                               .select(['name', 'college'])
#                               .where('name', 'Test Player')
#                               .run
#     puts "Selected player: #{result.inspect}\n"
  
#     # Update player's position
#     MySqliteRequest.new.from('nba_player_data_copy.csv')
#       .update('nba_player_data_copy.csv')
#       .where('name', 'Test Player')
#       .set({ 'position' => 'SG' })
#       .run
#     puts "Updated player's position to SG.\n"
  
#     # Check the updated player
#     updated_result = MySqliteRequest.new.from('nba_player_data_copy.csv')
#                                       .select(['name', 'position'])
#                                       .where('name', 'Test Player')
#                                       .run
#     puts "Updated player data: #{updated_result.inspect}\n"
  
#     # Delete the player (optional)
#     MySqliteRequest.new.from('nba_player_data_copy.csv')
#       .delete
#       .where('name', 'Test Player')
#       .run
#     puts "Deleted player: Test Player\n\n"
#   end

  
#   # Run all test cases
#   test_insert
#   test_select
#   test_update
#   test_delete
#   test_join
#   test_order
#   test_multiple_operations