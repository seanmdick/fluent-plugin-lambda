class Fluent::LambdaOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('lambda', self)

  include Fluent::SetTimeKeyMixin
  include Fluent::SetTagKeyMixin

  unless method_defined?(:log)
    define_method('log') { $log }
  end

  config_param :profile,                    :string, :default => nil
  config_param :credentials_path,           :string, :default => nil
  config_param :aws_key_id,                 :string, :default => nil
  config_param :aws_sec_key,                :string, :default => nil
  config_param :region,                     :string, :default => nil
  config_param :endpoint,                   :string, :default => nil
  config_param :function_name,              :string, :default => nil

  config_set_default :include_time_key, false
  config_set_default :include_tag_key,  false

  def initialize
    super
    require 'aws-sdk-core'
    require 'json'
  end

  def configure(conf)
    super

    aws_opts = {}

    if @profile
      credentials_opts = {:profile_name => @profile}
      credentials_opts[:path] = @credentials_path if @credentials_path
      credentials = Aws::SharedCredentials.new(credentials_opts)
      aws_opts[:credentials] = credentials
    end

    aws_opts[:access_key_id] = @aws_key_id if @aws_key_id
    aws_opts[:secret_access_key] = @aws_sec_key if @aws_sec_key
    aws_opts[:region] = @region if @region
    aws_opts[:endpoint] = @endpoint if @endpoint

    configure_aws(aws_opts)
  end

  def start
    super

    @client = create_client
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    chunk = chunk.to_enum(:msgpack_each)

    chunk.select {|tag, time, record|
      if @function_name or record['function_name']
        true
      else
        log.warn("`function_name` key does not exist: #{[tag, time, record].inspect}")
        false
      end
    }.each {|tag, time, record|
      func_name = @function_name || record['function_name']

      @client.invoke_async(
        :function_name => func_name,
        :invoke_args => JSON.dump(record),
      )
    }
  end

  private

  def configure_aws(options)
    Aws.config.update(options)
  end

  def create_client
    Aws::Lambda::Client.new
  end
end
