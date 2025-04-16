require_relative 'my_sqlite_request'

class MySqliteCLI
  def initialize
    @request = MySqliteRequest.new
    puts "Welcome to MySqlite Command-Line interface! Type 'help' for instructions or 'exit' to quit."
    start
  end

  def start
    loop do
      print "\nMySqlite> "
      input = gets.chomp.strip
      break if input.casecmp('exit').zero?

      case input.downcase
      when 'help'
        display_help
      else
        process_command(input)
      end
    end
  end

  def display_help
    puts <<~HELP
      Available commands:
      - SELECT columns FROM table WHERE column = value ORDER BY column ASC|DESC;
        * Use * to select all columns: SELECT * FROM table
      Example: SELECT name, age FROM users WHERE age > 30 ORDER BY name ASC;
    
      - INSERT INTO table (columns) VALUES (values);
      Example: INSERT INTO users (name, age) VALUES ('John Doe', 28);
    
      - UPDATE table SET column = value [WHERE column = value];
      Example: UPDATE users SET age = 29 WHERE name = 'John Doe';
    
      - DELETE FROM table [WHERE column = value];
      Example: DELETE FROM users WHERE name = 'John Doe';

      - JOIN: SELECT table_a.column, table_b.column FROM table_a JOIN table_b ON table_a.column = table_b.column;
      Example: SELECT name, college FROM nba_player_data JOIN nba_players ON nba_player_data.name = nba_players.Player;

      - Type 'exit' to quit.
    HELP
  end

  def process_command(input)
    begin
      if input.match?(/^SELECT/i)
        if input.match?(/JOIN/i)
          process_join(input)
        else
          process_select(input)
        end
      elsif input.match?(/^INSERT/i)
        process_insert(input)
      elsif input.match?(/^UPDATE/i)
        process_update(input)
      elsif input.match?(/^DELETE/i)
        process_delete(input)
      else
        puts "Invalid command. Type 'help' for instructions."
      end
    rescue StandardError => e
      puts "Error: #{e.message}"
    end
  end

  def process_select(input)
    # Enhanced regex to better handle different formats and optional clauses
    match = input.match(/^SELECT\s+(.+?)\s+FROM\s+(\S+?)(?:\.csv)?(?:\s+WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+(.+?))?;?$/i)
    if match
      columns, table, where, order = match.captures
      
      # Handle table extension
      table = "#{table}.csv" unless table.end_with?('.csv')
      
      # Process columns (handle * wildcard)
      column_list = columns.strip == '*' ? ['*'] : columns.split(',').map(&:strip)
      
      begin
        # Create a new request instance to avoid state issues
        request = MySqliteRequest.new
        
        request.from(table).select(column_list)
        
        if where
          where.split(/\s+AND\s+/i).each do |condition|
            parts = condition.split(/\s*([=<>])\s*/)
            if parts.length >= 3
              column = parts[0].strip
              operator = parts[1]
              value = parts[2..-1].join.strip
              value = remove_quotes(value)
              
              # Currently only supports equality
              if operator == '='
                request.where(column, value)
              else
                puts "Warning: Only equality (=) operator is fully supported in WHERE clauses."
                request.where(column, value)
              end
            end
          end
        end
        
        if order
          parts = order.split(/\s+/)
          if parts.length >= 1
            column = parts[0].strip
            direction = parts.length > 1 ? parts[1].downcase : 'asc'
            direction = direction.downcase == 'desc' ? :desc : :asc
            request.order(direction, column)
          end
        end
        
        # Run the query
        result = request.run
        
        # Handle the result
        if result.nil?
          puts "Query returned no results."
        else
          display_results(result)
        end
      rescue StandardError => e
        puts "Error executing SELECT: #{e.message}"
      end
    else
      puts "Invalid SELECT syntax. Use: SELECT columns FROM table [WHERE condition] [ORDER BY column ASC|DESC];"
    end
  end

  def process_insert(input)
    match = input.match(/^INSERT\s+INTO\s+(\S+?)(?:\.csv)?\s+\((.+?)\)\s+VALUES\s+\((.+?)\);?$/i)
    if match
      table, columns, values = match.captures
      
      # Prepare columns and values
      column_array = columns.split(',').map(&:strip)
      value_array = parse_values(values)
      
      # Create hash from columns and values
      data = {}
      column_array.each_with_index do |col, idx|
        data[col] = value_array[idx] if idx < value_array.length
      end
      
      @request.insert(table).values(data).run
      puts "Record inserted successfully."
    else
      puts "Invalid INSERT syntax. Use: INSERT INTO table (col1, col2) VALUES (val1, val2);"
    end
  end

  def process_update(input)
    match = input.match(/^UPDATE\s+(\S+?)(?:\.csv)?\s+SET\s+(.+?)(?:\s+WHERE\s+(.+?))?;?$/i)
    if match
      table, updates, where = match.captures
      
      begin
        # Create a new request instance to avoid state issues
        request = MySqliteRequest.new
        
        # Prepare update data
        update_data = {}
        updates.split(',').each do |u| 
          k, v = u.split('=', 2).map(&:strip)
          update_data[k] = remove_quotes(v)
        end
        
        # Set up the update operation
        request.update(table).set(update_data)
        
        # Add WHERE conditions if present
        if where
          where.split(/\s+AND\s+/i).each do |condition|
            parts = condition.split(/\s*([=<>])\s*/)
            if parts.length >= 3
              column = parts[0].strip
              value = parts[2..-1].join.strip
              value = remove_quotes(value)
              request.where(column, value)
            end
          end
        end
        
        # Execute the update
        result = request.run
        
        # Show appropriate message based on result
        if result && result[:status] == "success"
          puts "#{result[:message]}"
        elsif result && result[:status] == "warning"
          puts "Warning: #{result[:message]}"
        end
      rescue StandardError => e
        puts "Error executing UPDATE: #{e.message}"
      end
    else
      puts "Invalid UPDATE syntax. Use: UPDATE table SET column=value [WHERE condition];"
    end
  end

  def process_delete(input)
    match = input.match(/^DELETE\s+FROM\s+(\S+?)(?:\.csv)?(?:\s+WHERE\s+(.+?))?;?$/i)
    if match
      table, where = match.captures
      
      begin
        # Create a new request instance to avoid state issues
        request = MySqliteRequest.new
        
        request.from(table).delete
        
        if where
          where.split(/\s+AND\s+/i).each do |condition|
            parts = condition.split(/\s*([=<>])\s*/)
            if parts.length >= 3
              column = parts[0].strip
              value = parts[2..-1].join.strip
              value = remove_quotes(value)
              request.where(column, value)
            end
          end
        end
        
        result = request.run
        
        if result && result[:status] == "success"
          puts "#{result[:message]}"
        elsif result && result[:status] == "warning"
          puts "Warning: #{result[:message]}"
        end
      rescue StandardError => e
        puts "Error executing DELETE: #{e.message}"
      end
    else
      puts "Invalid DELETE syntax. Use: DELETE FROM table [WHERE condition];"
    end
  end

  def process_join(input)
    # Enhanced regex to better handle JOIN patterns
    match = input.match(/^SELECT\s+(.+?)\s+FROM\s+(\S+?)(?:\.csv)?\s+JOIN\s+(\S+?)(?:\.csv)?\s+ON\s+(\S+?\.\S+?)\s*=\s*(\S+?\.\S+?)(?:\s+WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+(.+?))?;?$/i)
    
    unless match
      puts "Invalid JOIN syntax. Use: SELECT cols FROM table1 JOIN table2 ON table1.col = table2.col [WHERE condition] [ORDER BY col];"
      return
    end
    
    begin
      columns, table_a, table_b, join_condition_a, join_condition_b, where, order = match.captures
    
      # Extract column names for the join without table prefixes
      join_table_a, join_col_a = join_condition_a.split('.')
      join_table_b, join_col_b = join_condition_b.split('.')
      
      # Verify that the join conditions match the specified tables
      # Strip .csv extension for comparison
      table_a_clean = table_a.sub(/\.csv$/i, '')
      table_b_clean = table_b.sub(/\.csv$/i, '')
      
      unless (join_table_a == table_a_clean) && (join_table_b == table_b_clean)
        puts "Join condition tables (#{join_table_a}, #{join_table_b}) don't match FROM and JOIN tables (#{table_a_clean}, #{table_b_clean})"
        return
      end
    
      # Process the columns - strip any table prefixes for cleaner output
      selected_columns = if columns.strip == '*'
        ['*']
      else
        columns.split(',').map(&:strip).map do |col|
          col.include?('.') ? col.split('.').last : col
        end
      end
    
      # Create a new request instance to avoid state issues
      request = MySqliteRequest.new
      
      # Set up the request
      request.from(table_a)
             .join(join_col_a, table_b, join_col_b)
             .select(selected_columns)
    
      # Process WHERE and ORDER BY clauses if present
      if where
        where.split(/\s+AND\s+/i).each do |condition|
          parts = condition.split(/\s*([=<>])\s*/)
          if parts.length >= 3
            column = parts[0].strip
            value = parts[2..-1].join.strip
            value = remove_quotes(value)
            request.where(column, value)
          end
        end
      end
      
      if order
        parts = order.split(/\s+/)
        if parts.length >= 1
          column = parts[0].strip
          direction = parts.length > 1 ? parts[1].downcase : 'asc'
          direction = direction.downcase == 'desc' ? :desc : :asc
          request.order(direction, column)
        end
      end
    
      # Execute the request
      result = request.run
      
      if result.nil? || result.empty?
        puts "JOIN query returned no results."
      else
        display_results(result)
      end
    rescue StandardError => e
      puts "Error executing JOIN: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
    end
  end

  def process_where(where_clause)
    where_clause.split(/\s+AND\s+/i).each do |condition|
      parts = condition.split(/\s*([=<>])\s*/)
      if parts.length >= 3
        column = parts[0].strip
        operator = parts[1]
        value = parts[2..-1].join.strip
        
        # Remove quotes from value if present
        value = remove_quotes(value)
        
        # Currently, the MySqliteRequest only supports equality, so we enforce that
        if operator == '='
          @request.where(column, value)
        else
          puts "Warning: Only equality (=) operator is fully supported in WHERE clauses."
          @request.where(column, value)
        end
      else
        puts "Invalid WHERE condition format: #{condition}"
      end
    end
  end

  def process_order(order_clause)
    parts = order_clause.split(/\s+/)
    if parts.length >= 1
      column = parts[0].strip
      direction = parts.length > 1 ? parts[1].downcase : 'asc'
      direction = direction.downcase == 'desc' ? :desc : :asc
      @request.order(direction, column)
    else
      puts "Invalid ORDER BY format: #{order_clause}"
    end
  end
  
  def display_results(result)
    if result && !result.empty?
      begin
        # Print the headers
        headers = result.first.keys
        puts headers.join("\t|\t")
        puts "-" * headers.join("\t|\t").length
        
        # Print each row
        result.each do |row|
          puts row.values.join("\t|\t")
        end
        puts "\n#{result.length} record(s) found."
      rescue NoMethodError => e
        puts "Error displaying results: #{e.message}"
        puts "Result type: #{result.class}, First item type: #{result.first.class if result.first}"
        puts "Raw result: #{result.inspect}"
      end
    else
      puts "No results found."
    end
  end
  
  # Parse VALUES part of INSERT statement, handling quoted strings
  def parse_values(values_str)
    values = []
    current_value = ""
    in_quotes = false
    
    values_str.each_char do |char|
      if char == "'" && !in_quotes
        in_quotes = true
      elsif char == "'" && in_quotes
        in_quotes = false
      elsif char == ',' && !in_quotes
        values << remove_quotes(current_value.strip)
        current_value = ""
      else
        current_value += char
      end
    end
    
    # Add the last value
    values << remove_quotes(current_value.strip) unless current_value.empty?
    values
  end
  
  # Remove quotes from a string value
  def remove_quotes(value)
    if value.start_with?("'") && value.end_with?("'")
      value[1...-1]
    else
      value
    end
  end
end

# Start the CLI if this file is run directly
if __FILE__ == $0
  MySqliteCLI.new
end