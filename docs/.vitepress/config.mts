import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'GDSQL',
  description: 'Database SQL Workbench Plugin for Godot Engine',
  base: '/GDSQL/',

  head: [
    ['meta', { name: 'theme-color', content: '#478CBF' }],
    ['meta', { name: 'og:type', content: 'website' }],
    ['meta', { name: 'og:title', content: 'GDSQL - Godot Database SQL Workbench' }],
    ['meta', { name: 'og:description', content: 'Database SQL Workbench Plugin for Godot Engine' }],
  ],

  themeConfig: {
    logo: '/logo.svg',
    socialLinks: [
      { icon: 'github', link: 'https://github.com/jinyangcruise/GDSQL' },
    ],
    search: {
      provider: 'local',
    },
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2024-present GDSQL Contributors',
    },
  },

  locales: {
    root: {
      label: 'English',
      lang: 'en',
      themeConfig: {
        nav: [
          { text: 'Guide', link: '/guide/getting-started' },
          { text: 'API Reference', link: '/api/base-dao' },
        ],
        sidebar: {
          '/guide/': [
            {
              text: 'Getting Started',
              items: [
                { text: 'Introduction', link: '/guide/introduction' },
                { text: 'Installation', link: '/guide/installation' },
                { text: 'Quick Start', link: '/guide/getting-started' },
                { text: 'Runtime Setup', link: '/guide/runtime-setup' },
                { text: 'Content + Save Models', link: '/guide/content-save-models' },
              ],
            },
            {
              text: 'Core Features',
              items: [
                { text: 'Visual Workbench', link: '/guide/workbench' },
                { text: 'SQL Query Engine', link: '/guide/sql-engine' },
                { text: 'Fluent DAO API', link: '/guide/dao-api' },
                { text: 'Smart Auto-Fill', link: '/guide/auto-fill' },
              ],
            },
            {
              text: 'Advanced',
              items: [
                { text: 'GBatis ORM', link: '/guide/gbatis' },
                { text: 'Mapper Graph Editor', link: '/guide/mapper-graph' },
                { text: 'Data Encryption', link: '/guide/encryption' },
                { text: 'XML Editor', link: '/guide/xml-editor' },
              ],
            },
            {
              text: 'More',
              items: [
                { text: 'Import & Export', link: '/guide/import-export' },
                { text: 'Limitations', link: '/guide/limitations' },
                { text: 'FAQ', link: '/guide/faq' },
              ],
            },
          ],
          '/api/': [
            {
              text: 'API Reference',
              items: [
                { text: 'BaseDao (Fluent API)', link: '/api/base-dao' },
                { text: 'QueryResult', link: '/api/query-result' },
                { text: 'SQL Parser', link: '/api/sql-parser' },
                { text: 'GBatisMapper', link: '/api/gbatis-mapper' },
                { text: 'GBatisEntity', link: '/api/gbatis-entity' },
                { text: 'CryptoUtil', link: '/api/crypto-util' },
                { text: 'ImprovedConfigFile', link: '/api/improved-config-file' },
              ],
            },
          ],
        },
      },
    },
    zh: {
      label: '简体中文',
      lang: 'zh-CN',
      link: '/zh/',
      themeConfig: {
        nav: [
          { text: '使用指南', link: '/zh/guide/getting-started' },
          { text: 'API 参考', link: '/zh/api/base-dao' },
        ],
        sidebar: {
          '/zh/guide/': [
            {
              text: '入门',
              items: [
                { text: '简介', link: '/zh/guide/introduction' },
                { text: '安装', link: '/zh/guide/installation' },
                { text: '快速开始', link: '/zh/guide/getting-started' },
              ],
            },
            {
              text: '核心功能',
              items: [
                { text: '可视化工作台', link: '/zh/guide/workbench' },
                { text: 'SQL 查询引擎', link: '/zh/guide/sql-engine' },
                { text: '链式 DAO API', link: '/zh/guide/dao-api' },
                { text: '智能自动填充', link: '/zh/guide/auto-fill' },
              ],
            },
            {
              text: '进阶功能',
              items: [
                { text: 'GBatis ORM 框架', link: '/zh/guide/gbatis' },
                { text: '映射图编辑器', link: '/zh/guide/mapper-graph' },
                { text: '数据加密', link: '/zh/guide/encryption' },
                { text: 'XML 编辑器', link: '/zh/guide/xml-editor' },
              ],
            },
            {
              text: '更多',
              items: [
                { text: '导入与导出', link: '/zh/guide/import-export' },
                { text: '局限性', link: '/zh/guide/limitations' },
                { text: '常见问题', link: '/zh/guide/faq' },
              ],
            },
          ],
          '/zh/api/': [
            {
              text: 'API 参考',
              items: [
                { text: 'BaseDao（链式 API）', link: '/zh/api/base-dao' },
                { text: 'QueryResult', link: '/zh/api/query-result' },
                { text: 'SQL Parser', link: '/zh/api/sql-parser' },
                { text: 'GBatisMapper', link: '/zh/api/gbatis-mapper' },
                { text: 'GBatisEntity', link: '/zh/api/gbatis-entity' },
                { text: 'CryptoUtil', link: '/zh/api/crypto-util' },
                { text: 'ImprovedConfigFile', link: '/zh/api/improved-config-file' },
              ],
            },
          ],
        },
      },
    },
  },
})
