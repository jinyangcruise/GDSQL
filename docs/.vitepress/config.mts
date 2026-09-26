import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'GDSQL',
  description: 'A Godot-native database workbench for authored content and saved state.',
  base: '/GDSQL/',
  srcExclude: [
    'api/**',
    'zh/**',
    'guide/auto-fill.md',
    'guide/dao-api.md',
    'guide/encryption.md',
    'guide/faq.md',
    'guide/gbatis.md',
    'guide/import-export.md',
    'guide/limitations.md',
    'guide/mapper-graph.md',
    'guide/sql-engine.md',
    'guide/workbench.md',
    'guide/xml-editor.md',
  ],

  head: [
    ['meta', { name: 'theme-color', content: '#478CBF' }],
    ['meta', { name: 'og:type', content: 'website' }],
    ['meta', { name: 'og:title', content: 'GDSQL for Godot' }],
    ['meta', {
      name: 'og:description',
      content: 'Create, inspect, and use typed game content and saved state inside Godot.',
    }],
  ],

  themeConfig: {
    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'Architecture', link: '/architecture/core' },
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Start here',
          items: [
            { text: 'Introduction', link: '/guide/introduction' },
            { text: 'Installation', link: '/guide/installation' },
            { text: 'Create your first project', link: '/guide/getting-started' },
            { text: 'Choose a content profile', link: '/guide/content-profiles' },
          ],
        },
        {
          text: 'Use your data',
          items: [
            { text: 'Runtime setup', link: '/guide/runtime-setup' },
            { text: 'Content and save models', link: '/guide/content-save-models' },
            { text: 'Model relationships', link: '/guide/model-relationships' },
          ],
        },
        {
          text: 'Integrations',
          items: [
            { text: 'Godot-AI tools', link: '/guide/godot-ai' },
          ],
        },
      ],
      '/architecture/': [
        {
          text: 'Architecture',
          items: [
            { text: 'Core boundaries', link: '/architecture/core' },
            { text: 'Glossary', link: '/architecture/glossary' },
            { text: 'MCP integration', link: '/architecture/mcp' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/jinyangcruise/GDSQL' },
    ],
    search: { provider: 'local' },
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2024-present GDSQL Contributors',
    },
  },
})
