# frozen_string_literal: true

# Uses Ruby YAML to handle kubeconfig entries
Puppet::Type.type(:kubeconfig).provide(:ruby) do
  def exists?
    return false unless File.exist? resource[:path]
    return true if resource[:ensure].to_s == 'absent'

    find_cluster
    find_context
    find_credentials

    return false if changed?
    return false unless valid?

    true
  end

  def create
    update_cluster
    update_context
    update_credentials
    update_current_context if resource[:current_context]

    save if changed?

    chown
    chmod
  end

  def destroy
    FileUtils.rm_f(resource[:path]) if File.exist?(resource[:path])
    @kubeconfig_hash = 0
  end

  def save
    File.write(resource[:path], Psych.dump(kubeconfig_content))
    @kubeconfig_hash = @kubeconfig_content.hash
  end

  def chown
    FileUtils.chown(resource[:owner], resource[:group], resource[:path])
  end

  def chmod
    mode = resource[:mode]
    raise Puppet::Error, 'File mode is invalid' unless mode.is_a?(String) && mode =~ %r{^0[0-7]{3}$}

    FileUtils.chmod(mode.to_i(8), resource[:path])
  end

  def find_cluster
    kubeconfig_content['clusters'] ||= []
    cluster = kubeconfig_content['clusters'].find { |c| c['name'] == resource[:cluster] }
    kubeconfig_content['clusters'] << (cluster = {}) unless cluster
    cluster
  end

  def find_context
    kubeconfig_content['contexts'] ||= []
    context = kubeconfig_content['contexts'].find { |c| c['name'] == resource[:context] }
    kubeconfig_content['contexts'] << (context = {}) unless context
    context
  end

  def find_credentials
    kubeconfig_content['users'] ||= []
    user = kubeconfig_content['users'].find { |c| c['name'] == resource[:context] }
    kubeconfig_content['users'] << (user = {}) unless user
    user
  end

  def valid?
    valid = true
    valid &&= cluster_valid?
    valid &&= context_valid?
    valid &&= credentials_valid?
    valid &&= current_context_valid? if resource[:current_context]
    valid &&= owner_valid? if resource[:owner]
    valid &&= group_valid? if resource[:group]
    valid
  end

  def cluster_valid?
    cluster = find_cluster

    return false unless cluster['name'] == resource[:cluster]
    return false unless cluster['cluster']
    return false if resource[:server] && cluster['cluster']['server'] != resource[:server]
    return false if resource[:skip_tls_verify] && cluster['cluster']['insecure-skip-tls-verify'] != (resource[:skip_tls_verify] == :true)
    return false if resource[:tls_server_name] && cluster['cluster']['tls-server-name'] != resource[:tls_server_name]

    if resource[:ca_cert]
      if resource[:embed_certs] == :true
        wanted = Base64.strict_encode64(File.read(resource[:ca_cert]))
        return false unless cluster['cluster']['certificate-authority-data'] == wanted
      else
        return false unless cluster['cluster']['certificate-authority'] == resource[:ca_cert]
      end
    end

    true
  end

  def update_cluster
    cluster = find_cluster

    cluster['name'] = resource[:cluster]
    cluster['cluster'] ||= {}
    cluster['cluster']['server'] = resource[:server] if resource[:server]
    cluster['cluster']['server'] ||= ''
    cluster['cluster']['insecure-skip-tls-verify'] = resource[:skip_tls_verify] == :true if resource[:skip_tls_verify]
    cluster['cluster']['tls-server-name'] = resource[:tls_server_name] if resource[:tls_server_name]

    return unless resource[:ca_cert]

    if resource[:embed_certs] == :true
      cluster['cluster']['certificate-authority-data'] = Base64.strict_encode64(File.read(resource[:ca_cert]))
    else
      cluster['cluster']['certificate-authority'] = resource[:ca_cert]
    end
  end

  def context_valid?
    context = find_context

    return false unless context['name'] == resource[:context]
    return false unless context['context']
    return false unless context['context']['cluster'] == resource[:cluster]
    return false unless context['context']['namespace'] == resource[:namespace]
    return false unless context['context']['user'] == resource[:user]

    true
  end

  def update_context
    context = find_context

    context['name'] = resource[:context]
    context['context'] ||= {}
    context['context']['cluster'] = resource[:cluster]
    context['context']['namespace'] = resource[:namespace]
    context['context']['user'] = resource[:user]
  end

  def credentials_valid?
    user = find_credentials

    return false unless user['name'] == resource[:user]
    return false unless user['user']

    if resource[:client_cert]
      if resource[:embed_certs] == :true
        wanted = Base64.strict_encode64(File.read(resource[:client_cert]))
        return false unless user['user']['client-certificate-data'] == wanted
      else
        return false unless user['user']['client-certificate'] == resource[:client_cert]
      end
    end
    if resource[:client_key]
      if resource[:embed_certs] == :true
        wanted = Base64.strict_encode64(File.read(resource[:client_key]))
        return false unless user['user']['client-key-data'] == wanted
      else
        return false unless user['user']['client-key'] == resource[:client_key]
      end
    end
    return false if resource[:token] && user['user']['token'] != resource[:token]
    return false if resource[:token_file] && user['user']['token'] != File.read(resource[:token_file].strip)
    return false if resource[:username] && user['user']['username'] != resource[:username]
    return false if resource[:password] && user['user']['password'] != resource[:password]

    true
  end

  def update_credentials
    user = find_credentials

    user['name'] = resource[:user]
    user['user'] ||= {}

    if resource[:client_cert]
      if resource[:embed_certs] == :true
        user['user']['client-certificate-data'] = Base64.strict_encode64(File.read(resource[:client_cert]))
      else
        user['user']['client-certificate'] = resource[:client_cert]
      end
    end
    if resource[:client_key]
      if resource[:embed_certs] == :true
        user['user']['client-key-data'] = Base64.strict_encode64(File.read(resource[:client_key]))
      else
        user['user']['client-key'] = resource[:client_key]
      end
    end

    user['user']['token'] = resource[:token] if resource[:token]
    user['user']['token'] = File.read(resource[:token_file]).strip if resource[:token_file]
    user['user']['username'] = resource[:username] if resource[:username]
    user['user']['password'] = resource[:password] if resource[:password]
  end

  def current_context_valid?
    kubeconfig_content['current-context'] == resource[:current_context]
  end

  def update_current_context
    kubeconfig_content['current-context'] = resource[:current_context]
  end

  def owner_valid?
    return false unless File.exist? resource[:path]

    uid = File.stat(resource[:path]).uid
    return true if uid == resource[:owner] || uid.to_s == resource[:owner].to_s

    uid = Etc.getpwuid(uid)
    uid.name == resource[:owner]
  rescue ArgumentError
    false
  end

  def group_valid?
    return false unless File.exist? resource[:path]

    gid = File.stat(resource[:path]).gid
    return true if gid == resource[:group] || gid.to_s == resource[:group].to_s

    gid = Etc.getgrgid(gid)
    gid.name == resource[:group]
  rescue ArgumentError
    false
  end

  def changed?
    Puppet.debug(self.to_s + ": " + "kubeconfig_content=#{kubeconfig_content}")
    Puppet.debug(self.to_s + ": " + "kubeconfig_content.hash=#{kubeconfig_content.hash}")
    Puppet.debug(self.to_s + ": " + "@kubeconfig_hash=#{@kubeconfig_hash}")
    kubeconfig_content.hash != @kubeconfig_hash
  end

  def kubeconfig_content
    default = {
      'apiVersion' => 'v1',
      'clusters' => [],
      'contexts' => [],
      'users' => [],
      'current-context' => 'default',
      'kind' => 'Config',
      'preferences' => {},
    }

    @kubeconfig_content ||= \
      if File.exist? resource[:path]
        begin
          data = Psych.load(File.read(resource[:path]))
        rescue Psych::Exception
          Puppet.debug(self.to_s + ": " + "error reading #{resource[:path]}")
          data = {} # Handle broken files as if empty
        end
        data = {} unless data.is_a? Hash
        default.merge data
      else
        default
      end
    @kubeconfig_hash ||= @kubeconfig_content.hash
    @kubeconfig_content
  end
end
