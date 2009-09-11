class RequestLogAnalyzer::Database::Base < ActiveRecord::Base
  
  self.abstract_class = true

  def <=>(other)
    if (source_comparison = source_id <=> other.source_id) == 0
      lineno <=> other.lineno
    else
      source_comparison
    end
  end

  def line_type
    self.class.name.underscore.gsub(/_line$/, '').to_sym
  end

  cattr_accessor :database, :line_definition

  def self.subclass_from_line_definition(definition)
    klass = Class.new(RequestLogAnalyzer::Database::Base)
    klass.set_table_name("#{definition.name}_lines")
    
    klass.line_definition = definition
    
    # Set relations with requests and sources table
    klass.belongs_to :request
    klass.belongs_to :source
    
    # Serialize complex fields into the database
    definition.captures.select { |c| c.has_key?(:provides) }.each do |capture|
      klass.send(:serialize, capture[:name], Hash)
    end

    self.database.request_class.send :has_many, "#{definition.name}_lines".to_sym
    self.database.source_class.send  :has_many, "#{definition.name}_lines".to_sym
    
    return klass
  end
  
  def self.subclass_from_table(table)
    raise "Table #{table} not found!" unless database.connection.table_exists?(table)

    klass = Class.new(RequestLogAnalyzer::Database::Base)
    klass.set_table_name(table)

    if klass.column_names.include?('request_id')
      klass.send :belongs_to, :request
      database.request_class.send :has_many, table.to_sym
    end
    
    if klass.column_names.include?('source_id')
      klass.send :belongs_to, :source
      database.source_class.send :has_many, table.to_sym
    end
    
    return klass
  end
  
  def self.drop_table!
    self.database.connection.drop_table(self.table_name) if database.connection.table_exists?(self.table_name)
  end
  
  def self.create_table!
    raise "No line_definition available to base table schema on!" unless self.line_definition
    
    unless table_exists?
      self.database.connection.create_table(self.table_name.to_sym) do |t|
      
        # Default fields
        t.column :request_id, :integer
        t.column :source_id,  :integer
        t.column :lineno,     :integer
      
        line_definition.captures.each do |capture|
          # Add a field for every capture
          t.column(capture[:name], column_type(capture[:type]))

          # If the capture provides other field as well, create columns for them, too
          capture[:provides].each { |field, field_type| t.column(field, column_type(field_type)) } if capture[:provides].kind_of?(Hash)
        end
      end
    end
    
    # Add indices to table for more speedy querying
    self.database.connection.add_index(self.table_name.to_sym, [:request_id])
    self.database.connection.add_index(self.table_name.to_sym, [:source_id])
  end
  
  
  # Function to determine the column type for a field
  # TODO: make more robust / include in file-format definition
  def self.column_type(type_indicator)
    case type_indicator
    when :eval;      :text
    when :hash;      :text
    when :text;      :text
    when :string;    :string
    when :sec;       :double
    when :msec;      :double
    when :duration;  :double
    when :float;     :double
    when :double;    :double
    when :integer;   :integer
    when :int;       :int
    when :timestamp; :datetime
    when :datetime;  :datetime
    when :date;      :date
    else             :string
    end
  end  
  
end