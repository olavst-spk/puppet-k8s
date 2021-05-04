require 'spec_helper'

kubectl_provider = Puppet::Type.type(:kubectl_apply).provider(:kubectl)

RSpec.describe kubectl_provider do
  describe 'kubectl provider' do
    include PuppetlabsSpec::Files
    let(:tmpfile) do
      tmpfilename('kubeconfig_test')
    end

    let(:name) { 'bootstrap-token-example' }
    let(:resource_properties) do
      {
        ensure: :present,
        name: name,
        namespace: 'kube-system',

        api_version: 'v1',
        kind: 'Secret',

        content: {
          metadata: {
            annotations: {
              'example.com/spec': 'true',
            }
          },
          type: 'bootstrap.kubernetes.io/token',
          data: {
            'token-id': 'tokenid',
            'token-secret': 'tokensecret',
            'usage-bootstrap-authentication': 'true',
          }
        }
      }
    end

    let(:kubectl_params) do
      [
        '--namespace',
        'kube-system',
        'get',
        'Secret',
        name,
        '--output',
        'json',
      ]
    end

    let(:resource) { Puppet::Type::Kubectl_apply.new(resource_properties) }
    let(:provider) { kubectl_provider.new(resource) }

    before(:each) do
      resource.provider = provider

      allow(kubectl_provider).to receive(:suitable?).and_return(true)
    end

    context 'when identical' do
      let(:upstream_data) do
        {
          apiVersion: 'v1',
          data: {
            'token-id': 'tokenid',
            'token-secret': 'tokensecret',
            'usage-bootstrap-authentication': 'true',
          },
          kind: 'Secret',
          metadata: {
            annotations: {
              'example.com/spec': 'true',
              'example.kubernetes.io/attribute': 'generated',
            },
            creationTimestamp: '2021-03-08T15:36:30Z',
            name: 'bootstrap-token-example',
            namespace: 'kube-system',
            resourceVersion: '281179626',
            selfLink: '/api/v1/namespaces/kube-system/secrets/bootstrap-token-example',
            uid: 'f19909a0-f5c6-4945-b79e-c4c3c386c345',
          },
          type: 'bootstrap.kubernetes.io/token',
        }
      end

      it 'generates a valid resource hash' do
        expect(provider.resource_hash).to eq resource_properties[:content].merge(
          'apiVersion' => 'v1',
          'kind' => 'Secret',
          'metadata' => {
            'name' => 'bootstrap-token-example',
            'namespace' => 'kube-system',
          },
        )
      end

      it 'calls kubectl to retrieve resource' do
        expect(provider).to receive(:kubectl).with(*kubectl_params).and_return upstream_data.to_json
        expect(provider.send(:kubectl_get)).to eq JSON.parse(upstream_data.to_json)
      end

      it 'correctly verifies the expanded upstream resource hash' do
        expect(provider.content_diff(upstream_data)).to eq({})
      end

      it 'creates the resource if not existing' do
        file = instance_double('Tempfile')
        expect(file).to receive(:path).and_return('/tmp/kubectl_apply')
        expect(file).to receive(:write).with(provider.resource_hash.to_json)
        expect(file).to receive(:close!)
        expect(Tempfile).to receive(:new).with('kubectl_apply').and_return(file)

        expect(provider).to receive(:kubectl).with('--namespace', 'kube-system', 'create', '-f', '/tmp/kubectl_apply')

        provider.create
      end

      it 'applies without action if exists' do
        expect(provider).to receive(:kubectl).never
        expect(provider).to receive(:exists?).and_return(true)
        expect(provider).to receive(:create).never
        expect(provider).to receive(:resource_diff).never

        allow(Puppet::Util::Storage).to receive(:store)

        catalog = Puppet::Resource::Catalog.new
        catalog.add_resource(resource)
        logs = catalog.apply.report.logs

        expect(logs.empty?).to eq(true)
      end
    end

    context 'when data differs' do
      let(:upstream_data) do
        {
          apiVersion: 'v1',
          data: {
            'token-id': 'other-token-id',
            'token-secret': 'tokensecret',
            'usage-bootstrap-authentication': 'true',
          },
          kind: 'Secret',
          metadata: {
            annotations: {
              'example.com/spec': 'true',
              'example.kubernetes.io/attribute': 'generated',
            },
            creationTimestamp: '2021-03-08T15:36:30Z',
            name: 'bootstrap-token-example',
            namespace: 'kube-system',
            resourceVersion: '281179626',
            selfLink: '/api/v1/namespaces/kube-system/secrets/bootstrap-token-example',
            uid: 'f19909a0-f5c6-4945-b79e-c4c3c386c345',
          },
          type: 'bootstrap.kubernetes.io/token',
        }
      end

      it 'correctly verifies the larger upstream resource hash' do
        expect(provider.content_diff(upstream_data)).not_to eq({})
      end

      it 'applies with a patch' do
        file = instance_double('Tempfile')
        expect(file).to receive(:path).and_return('/tmp/kubectl_apply')
        expect(file).to receive(:write).with(provider.resource_hash.to_json)
        expect(file).to receive(:close!)
        expect(Tempfile).to receive(:new).with('kubectl_apply').and_return(file)

        allow(provider).to receive(:resource_diff).and_return(provider.content_diff(upstream_data))
        expect(provider).to receive(:kubectl).with('--namespace', 'kube-system', 'patch', '-f', '/tmp/kubectl_apply', '-p', '{"data":{"token-id":"tokenid"}}')

        provider.create
      end

      it 'returns a reasonable difference output' do
        expect(provider).to receive(:kubectl).never
        allow(provider).to receive(:exists?).and_return(false)
        expect(provider).to receive(:create).and_return(true)
        allow(provider).to receive(:resource_diff).and_return(provider.content_diff(upstream_data))

        allow(Puppet::Util::Storage).to receive(:store)

        catalog = Puppet::Resource::Catalog.new
        catalog.add_resource(resource)
        report = catalog.apply.report
        logs = report.logs

        expect(logs.first.source).to eq('/Kubectl_apply[bootstrap-token-example]/ensure')
        expect(logs.first.message).to eq('update Secret kube-system/bootstrap-token-example with {"data"=>{"token-id"=>"tokenid"}}')
      end
    end

    context 'when data is missing' do
      let(:upstream_data) do
        {
          apiVersion: 'v1',
          data: {
            'token-id': 'tokenid',
            'token-secret': 'tokensecret',
            'usage-bootstrap-authentication': 'true',
          },
          kind: 'Secret',
          metadata: {
            annotations: {
              'example.kubernetes.io/attribute': 'generated',
            },
            creationTimestamp: '2021-03-08T15:36:30Z',
            name: 'bootstrap-token-example',
            namespace: 'kube-system',
            resourceVersion: '281179626',
            selfLink: '/api/v1/namespaces/kube-system/secrets/bootstrap-token-example',
            uid: 'f19909a0-f5c6-4945-b79e-c4c3c386c345',
          },
          type: 'bootstrap.kubernetes.io/token',
        }
      end

      it 'correctly verifies the larger upstream resource hash' do
        expect(provider.content_diff(upstream_data)).not_to eq({})
      end
    end

    context 'with kubeconfig' do
      let(:resource_properties) do
        {
          name: name,
          namespace: 'kube-system',
          kubeconfig: '/root/kube/.config',

          api_version: 'v1',
          kind: 'Secret',

          content: {
            type: 'bootstrap.kubernetes.io/token',
            data: {
              'token-id': 'tokenid',
              'token-secret': 'tokensecret',
              'usage-bootstrap-authentication': 'true',
            }
          }
        }
      end

      let(:kubectl_params) do
        [
          '--namespace',
          'kube-system',
          '--kubeconfig',
          '/root/kube/.config',
          'get',
          'Secret',
          name,
          '--output',
          'json',
        ]
      end

      it 'calls kubectl to retrieve resource' do
        expect(provider).to receive(:kubectl).with(*kubectl_params).and_return({ data: 'value' }.to_json)

        expect(provider.send(:kubectl_get)).to eq({ 'data' => 'value' })
      end
    end

    context 'when absent' do
      let(:resource_properties) do
        {
          ensure: :absent,
          name: name,
          namespace: 'kube-system',

          api_version: 'v1',
          kind: 'Secret',
        }
      end

      it 'applies correctly' do
        expect(provider).to receive(:kubectl).never
        allow(provider).to receive(:exists?).and_return(true)
        expect(provider).to receive(:create).never
        expect(provider).to receive(:destroy)

        allow(Puppet::Util::Storage).to receive(:store)

        catalog = Puppet::Resource::Catalog.new
        catalog.add_resource(resource)
        logs = catalog.apply.report.logs

        expect(logs.first.source).to eq('/Kubectl_apply[bootstrap-token-example]/ensure')
        expect(logs.first.message).to eq('remove Secret kube-system/bootstrap-token-example')
      end
    end
  end
end