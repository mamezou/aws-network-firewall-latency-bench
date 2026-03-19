import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as networkfirewall from "aws-cdk-lib/aws-networkfirewall";
import * as iam from "aws-cdk-lib/aws-iam";
import * as logs from "aws-cdk-lib/aws-logs";

/**
 * AWS Network Firewall レイテンシーベンチマーク検証スタック
 *
 * 【構成概要】
 * 同一AZ内に3サブネット (Client / Firewall / Server) を配置し、
 * NFWエンドポイント経由 vs 同一サブネット直接通信でレイテンシーを比較する。
 *
 *   経路A (Firewall経由):
 *     ClientInst → NFW Endpoint → ServerInst
 *
 *   経路B (直接):
 *     ClientInst → BaselineInst (同一サブネット)
 *
 * 【テスト段階】
 *   Phase 0: ベースライン (NFW経由なし)
 *   Phase 1: ステートレスルールのみ (pass all)
 *   Phase 2: ステートフルルール追加 (Suricata pass all)
 *   Phase 3: TLS検査有効化
 *
 * 【ルートテーブル設定】
 *   NFWエンドポイントIDはデプロイ後にしか取得できないため、
 *   scripts/setup-routes.sh を手動実行する。
 *   CfnOutput の ClientSubnetRouteTableId / ServerSubnetRouteTableId を使用。
 *
 * 【Phase 3 TLS検査セットアップ】
 *   TLS inspection configurationはデプロイ後に scripts/switch-phase.sh 3 が自動作成する。
 *   (自己署名証明書の生成 → ACMインポート → TLS設定作成 → ポリシー関連付け)
 */
export class NfwLatencyBenchStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // ========================================
    // VPC: 3つのサブネットグループ (Client / Firewall / Server)
    // ========================================
    const vpc = new ec2.Vpc(this, "BenchVpc", {
      ipAddresses: ec2.IpAddresses.cidr("10.0.0.0/16"),
      maxAzs: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: "Client",
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: "Firewall",
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: "Server",
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // SSM用VPCエンドポイント (インターネット不要でSSM接続するため)
    vpc.addInterfaceEndpoint("SsmEndpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.SSM,
    });
    vpc.addInterfaceEndpoint("SsmMessagesEndpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
    });
    vpc.addInterfaceEndpoint("Ec2MessagesEndpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
    });

    // S3 VPCゲートウェイエンドポイント
    // Amazon Linux 2023 のパッケージリポジトリはS3経由で配信される。
    // Private Isolated サブネットからパッケージインストールするために必要。
    vpc.addGatewayEndpoint("S3Endpoint", {
      service: ec2.GatewayVpcEndpointAwsService.S3,
    });

    // サブネット参照
    const clientSubnets = vpc.selectSubnets({ subnetGroupName: "Client" });
    const firewallSubnets = vpc.selectSubnets({ subnetGroupName: "Firewall" });
    const serverSubnets = vpc.selectSubnets({ subnetGroupName: "Server" });

    // ========================================
    // セキュリティグループ
    // ========================================
    const benchSg = new ec2.SecurityGroup(this, "BenchSg", {
      vpc,
      description: "Allow ICMP, iperf3, HTTPS between bench instances",
      allowAllOutbound: true,
    });
    benchSg.addIngressRule(
      ec2.Peer.ipv4("10.0.0.0/16"),
      ec2.Port.allIcmp(),
      "ICMP from VPC"
    );
    benchSg.addIngressRule(
      ec2.Peer.ipv4("10.0.0.0/16"),
      ec2.Port.tcp(5201),
      "iperf3 from VPC"
    );
    benchSg.addIngressRule(
      ec2.Peer.ipv4("10.0.0.0/16"),
      ec2.Port.tcp(443),
      "HTTPS from VPC (Phase 3 TLS inspection)"
    );

    // ========================================
    // IAMロール (SSM接続用)
    // ========================================
    const instanceRole = new iam.Role(this, "InstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName("AmazonSSMManagedInstanceCore"),
      ],
    });

    // ========================================
    // EC2 UserData
    // ※ hping3 は AL2023 リポジトリに存在しないため nmap (nping) を使用
    // ========================================
    const clientUserData = ec2.UserData.forLinux();
    clientUserData.addCommands(
      "dnf install -y iperf3 nmap jq bc",
      "iperf3 -s -D"
    );

    // Server / Baseline用 (nginx + HTTPS設定 - Phase 3 TLS計測で使用)
    // 注意: nginx conf.d のヒアドキュメントは UserData では動作しないため printf を使用
    const serverUserData = ec2.UserData.forLinux();
    serverUserData.addCommands(
      "dnf install -y iperf3 nmap jq bc nginx",
      "iperf3 -s -D",
      // self-signed証明書の生成 (Phase 3 TLS検査用)
      // mkdir を openssl より先に実行すること
      "mkdir -p /etc/nginx/ssl",
      'openssl req -x509 -nodes -newkey rsa:2048 -days 365' +
        ' -keyout /etc/nginx/ssl/server.key' +
        ' -out /etc/nginx/ssl/server.crt' +
        ' -subj "/CN=bench-server" 2>/dev/null',
      // nginx HTTPS設定 (heredoc不可のため printf で書き込む)
      'printf "server {\\n    listen 443 ssl;\\n    ssl_certificate /etc/nginx/ssl/server.crt;\\n    ssl_certificate_key /etc/nginx/ssl/server.key;\\n    location / { return 200 \\"ok\\"; }\\n}\\n"' +
        " > /etc/nginx/conf.d/bench-https.conf",
      "systemctl enable nginx",
      "systemctl start nginx"
    );

    // ========================================
    // EC2インスタンス × 3 (c5.large: ENA対応でネットワーク性能安定)
    // ========================================
    const clientInstance = new ec2.Instance(this, "ClientInstance", {
      vpc,
      vpcSubnets: clientSubnets,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2023(),
      securityGroup: benchSg,
      role: instanceRole,
      userData: clientUserData,
    });

    const serverInstance = new ec2.Instance(this, "ServerInstance", {
      vpc,
      vpcSubnets: serverSubnets,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2023(),
      securityGroup: benchSg,
      role: instanceRole,
      userData: serverUserData,
    });

    // BaselineInst: ClientSubnetに配置 (NFW経由しない直接通信の比較用)
    const baselineInstance = new ec2.Instance(this, "BaselineInstance", {
      vpc,
      vpcSubnets: clientSubnets,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2023(),
      securityGroup: benchSg,
      role: instanceRole,
      userData: serverUserData,
    });

    // ========================================
    // Network Firewall
    // ========================================

    // ステートレスルールグループ: TCP + ICMP を pass
    const statelessRuleGroup = new networkfirewall.CfnRuleGroup(
      this,
      "StatelessPassAll",
      {
        ruleGroupName: "bench-stateless-pass-all",
        type: "STATELESS",
        capacity: 10,
        ruleGroup: {
          rulesSource: {
            statelessRulesAndCustomActions: {
              statelessRules: [
                {
                  priority: 1,
                  ruleDefinition: {
                    matchAttributes: {
                      protocols: [6], // TCP
                      sources: [{ addressDefinition: "0.0.0.0/0" }],
                      destinations: [{ addressDefinition: "0.0.0.0/0" }],
                    },
                    actions: ["aws:pass"],
                  },
                },
                {
                  priority: 2,
                  ruleDefinition: {
                    matchAttributes: {
                      protocols: [1], // ICMP
                      sources: [{ addressDefinition: "0.0.0.0/0" }],
                      destinations: [{ addressDefinition: "0.0.0.0/0" }],
                    },
                    actions: ["aws:pass"],
                  },
                },
              ],
            },
          },
        },
      }
    );

    // ステートフルルールグループ (DEFAULT_ACTION_ORDER): Phase 1/2 用
    const statefulRuleGroup = new networkfirewall.CfnRuleGroup(
      this,
      "StatefulPassAll",
      {
        ruleGroupName: "bench-stateful-pass-all",
        type: "STATEFUL",
        capacity: 100,
        ruleGroup: {
          rulesSource: {
            rulesString: [
              'pass icmp any any -> any any (msg:"Allow ICMP"; sid:1000001; rev:1;)',
              'pass tcp any any -> any 5201 (msg:"Allow iperf3"; sid:1000002; rev:1;)',
              'pass tcp any any -> any 443 (msg:"Allow HTTPS"; sid:1000003; rev:1;)',
            ].join("\n"),
          },
        },
      }
    );

    // ステートフルルールグループ (STRICT_ORDER): Phase 3 (TLS inspection) 専用
    // TLS inspection configuration は STRICT_ORDER を要求するため別グループが必要
    const statefulRuleGroupStrict = new networkfirewall.CfnRuleGroup(
      this,
      "StatefulPassAllStrict",
      {
        ruleGroupName: "bench-stateful-strict-pass-all",
        type: "STATEFUL",
        capacity: 100,
        ruleGroup: {
          statefulRuleOptions: {
            ruleOrder: "STRICT_ORDER",
          },
          rulesSource: {
            rulesString: [
              'pass icmp any any -> any any (msg:"Allow ICMP"; sid:1000001; rev:1;)',
              'pass tcp any any -> any 5201 (msg:"Allow iperf3"; sid:1000002; rev:1;)',
              'pass tcp any any -> any 443 (msg:"Allow HTTPS"; sid:1000003; rev:1;)',
            ].join("\n"),
          },
        },
      }
    );

    // ファイアウォールポリシー (Phase 1/2 用、デフォルト: Phase 2 状態)
    // switch-phase.sh でポリシー内容を切り替える:
    //   Phase 1: statelessDefaultActions = aws:pass、statefulRuleGroup なし
    //   Phase 2: statelessDefaultActions = aws:forward_to_sfe (このデフォルト状態)
    const firewallPolicy = new networkfirewall.CfnFirewallPolicy(
      this,
      "BenchFwPolicy",
      {
        firewallPolicyName: "bench-fw-policy",
        firewallPolicy: {
          statelessDefaultActions: ["aws:forward_to_sfe"],
          statelessFragmentDefaultActions: ["aws:forward_to_sfe"],
          statelessRuleGroupReferences: [
            {
              resourceArn: statelessRuleGroup.attrRuleGroupArn,
              priority: 1,
            },
          ],
          statefulRuleGroupReferences: [
            {
              resourceArn: statefulRuleGroup.attrRuleGroupArn,
            },
          ],
        },
      }
    );

    // Phase 3用ポリシー (STRICT_ORDER + TLS inspection)
    // TLS inspection configuration ARN はデプロイ後に switch-phase.sh 3 が設定する。
    // (自己署名証明書 → ACMインポート → TLS設定作成 → このポリシーを更新して関連付け)
    const firewallPolicyPhase3 = new networkfirewall.CfnFirewallPolicy(
      this,
      "BenchFwPolicyPhase3",
      {
        firewallPolicyName: "bench-fw-policy-phase3",
        firewallPolicy: {
          statelessDefaultActions: ["aws:forward_to_sfe"],
          statelessFragmentDefaultActions: ["aws:forward_to_sfe"],
          statelessRuleGroupReferences: [
            {
              resourceArn: statelessRuleGroup.attrRuleGroupArn,
              priority: 1,
            },
          ],
          statefulEngineOptions: {
            ruleOrder: "STRICT_ORDER",
          },
          statefulRuleGroupReferences: [
            {
              resourceArn: statefulRuleGroupStrict.attrRuleGroupArn,
              priority: 1,
            },
          ],
          // tlsInspectionConfigurationArn は switch-phase.sh 3 で追加
        },
      }
    );

    // Network Firewall 本体 (Phase 1/2 ポリシーで起動)
    const firewall = new networkfirewall.CfnFirewall(this, "BenchFirewall", {
      firewallName: "bench-nfw",
      firewallPolicyArn: firewallPolicy.attrFirewallPolicyArn,
      vpcId: vpc.vpcId,
      subnetMappings: firewallSubnets.subnetIds.map((id) => ({
        subnetId: id,
      })),
    });

    // フローログを CloudWatch Logs に出力 (retention: 1 week)
    const fwLogGroup = new logs.LogGroup(this, "FwLogGroup", {
      logGroupName: "/aws/network-firewall/bench",
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new networkfirewall.CfnLoggingConfiguration(this, "FwLogging", {
      firewallArn: firewall.ref,
      loggingConfiguration: {
        logDestinationConfigs: [
          {
            logType: "FLOW",
            logDestinationType: "CloudWatchLogs",
            logDestination: {
              logGroup: fwLogGroup.logGroupName,
            },
          },
        ],
      },
    });

    // ========================================
    // タグ (全リソースに付与)
    // ========================================
    cdk.Tags.of(this).add("Project", "nfw-latency-bench");
    cdk.Tags.of(this).add("Purpose", "benchmark");

    // ========================================
    // CfnOutput
    // ========================================
    new cdk.CfnOutput(this, "ClientInstanceId", {
      value: clientInstance.instanceId,
      description: "Client instance ID (SSM接続元)",
    });
    new cdk.CfnOutput(this, "ServerInstanceId", {
      value: serverInstance.instanceId,
      description: "Server instance ID (NFW経由の計測先)",
    });
    new cdk.CfnOutput(this, "BaselineInstanceId", {
      value: baselineInstance.instanceId,
      description: "Baseline instance ID (直接通信の比較先)",
    });
    new cdk.CfnOutput(this, "ServerPrivateIp", {
      value: serverInstance.instancePrivateIp,
    });
    new cdk.CfnOutput(this, "BaselinePrivateIp", {
      value: baselineInstance.instancePrivateIp,
    });
    new cdk.CfnOutput(this, "FirewallId", {
      value: firewall.ref,
    });
    new cdk.CfnOutput(this, "VpcId", {
      value: vpc.vpcId,
    });
    new cdk.CfnOutput(this, "ClientSubnetRouteTableId", {
      value: clientSubnets.subnets[0].routeTable.routeTableId,
      description: "setup-routes.sh の CLIENT_RT_ID に使用",
    });
    new cdk.CfnOutput(this, "ServerSubnetRouteTableId", {
      value: serverSubnets.subnets[0].routeTable.routeTableId,
      description: "setup-routes.sh の SERVER_RT_ID に使用",
    });
    new cdk.CfnOutput(this, "FirewallPolicyArn", {
      value: firewallPolicy.attrFirewallPolicyArn,
      description: "Phase 1/2 用ポリシー ARN (switch-phase.sh で使用)",
    });
    new cdk.CfnOutput(this, "Phase3FirewallPolicyArn", {
      value: firewallPolicyPhase3.attrFirewallPolicyArn,
      description: "Phase 3 用ポリシー ARN (switch-phase.sh 3 で使用)",
    });
    new cdk.CfnOutput(this, "StatelessRuleGroupArn", {
      value: statelessRuleGroup.attrRuleGroupArn,
    });
    new cdk.CfnOutput(this, "StatefulRuleGroupArn", {
      value: statefulRuleGroup.attrRuleGroupArn,
      description: "Phase 1/2 用 (DEFAULT_ACTION_ORDER)",
    });
    new cdk.CfnOutput(this, "StrictStatefulRuleGroupArn", {
      value: statefulRuleGroupStrict.attrRuleGroupArn,
      description: "Phase 3 用 (STRICT_ORDER)",
    });
  }
}
