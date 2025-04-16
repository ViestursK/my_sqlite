# MISSING - JOIN FUNCTIONALITY + HELP INFO + JOIN EXAMPLE IN README

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
    match = input.match(/^SELECT (.+?) FROM (\S+)(?: \[?WHERE (.+?)\]?)?(?: \[?ORDER BY (.+?)\]?)?;$/i)
    if match
      columns, table, where, order = match.captures
      @request.from(table).select(columns.split(','))
      process_where(where) if where
      process_order(order) if order
      @request.run
    else
      puts "Invalid SELECT syntax."
    end
  end

  def process_insert(input)
    match = input.match(/^INSERT INTO (\S+) \((.+?)\) VALUES \((.+?)\);$/i)
    if match
      table, columns, values = match.captures
      data = Hash[columns.split(',').zip(values.split(','))]
      @request.insert(table).values(data).run
    else
      puts "Invalid INSERT syntax."
    end
  end

  def process_update(input)
    match = input.match(/^UPDATE (\S+) SET (.+?)(?: WHERE (.+?))?;$/i)
    if match
      table, updates, where = match.captures
      update_data = Hash[updates.split(',').map { |u| u.split('=').map(&:strip) }]
      @request.update(table).set(update_data)
      process_where(where) if where
      @request.run
    else
      puts "Invalid UPDATE syntax."
    end
  end

  def process_delete(input)
    match = input.match(/^DELETE FROM (\S+)(?: WHERE (.+?))?;$/i)
    if match
      table, where = match.captures
      @request.from(table).delete
      process_where(where) if where
      @request.run
    else
      puts "Invalid DELETE syntax."
    end
  end

  def process_join(input)
    # Match the JOIN query pattern
    match = input.match(/^SELECT (.+?) FROM (\S+?)(\.csv)? JOIN (\S+?)(\.csv)? ON (\S+?\.\S+?)\s*=\s*(\S+?\.\S+?)(?: WHERE (.+?))?(?: ORDER BY (.+?))?;$/i)
    unless match
      puts "Invalid JOIN syntax."
      return
    end
  
    columns, table_a, table_a_ext, table_b, table_b_ext, join_condition_a, join_condition_b, where, order = match.captures
  
    # Add .csv extension if not present
    table_a = "#{table_a}#{table_a_ext || '.csv'}"
    table_b = "#{table_b}#{table_b_ext || '.csv'}"
  
    # Extract column names for the join without table prefixes
    join_table_a, join_col_a = join_condition_a.split('.')
    join_table_b, join_col_b = join_condition_b.split('.')
    
    # Verify that the join conditions match the specified tables
    unless (join_table_a == table_a.chomp('.csv') || join_table_a == table_a) &&
           (join_table_b == table_b.chomp('.csv') || join_table_b == table_b)
      puts "Join condition tables don't match FROM and JOIN tables"
      return
    end
  
    # Process the columns - strip any table prefixes
    selected_columns = columns.split(',').map(&:strip).map do |col|
      col.include?('.') ? col.split('.').last : col
    end
  
    # Set up the request
    @request.from(table_a)
            .join(join_col_a, table_b, join_col_b)  # Use the extracted column names without table prefixes
            .select(selected_columns)
  
    # Process WHERE and ORDER BY clauses if present
    process_where(where) if where
    process_order(order) if order
  
    # Execute the request
    result = @request.run
    
    if result && !result.empty?
      puts "Query executed successfully:"
      result.each do |row|
        puts row.inspect
      end
    else
      puts "No results found or join operation failed."
    end
  end

  def process_where(where_clause)
    where_clause.split('AND').each do |condition|
      column, value = condition.split('=').map(&:strip)
      @request.where(column, value)
    end
  end

  def process_order(order_clause)
    column, direction = order_clause.split
    direction = direction.downcase == 'desc' ? :desc : :asc
    @request.order(direction, column.strip)
  end
end

# Start the CLI
MySqliteCLI.new