import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'GDSQL',
  description: 'A Godot-native database workbench for authored content and saved state.',
  base: '/GDSQL/',
  srcExclude: [
    'api/**',
    'zh/**',
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
            { text: 'Managed content packages', link: '/guide/managed-content' },
          ],
        },
        {
          text: 'Author data',
          items: [
            { text: 'Table workbench', link: '/guide/table-workbench' },
            { text: 'Schemas and constraints', link: '/guide/schema-and-constraints' },
            { text: 'Resource columns', link: '/guide/resource-columns' },
          ],
        },
        {
          text: 'Use data at runtime',
          items: [
            { text: 'Runtime and models', link: '/guide/runtime-and-models' },
            { text: 'Relationships', link: '/guide/relationships' },
            { text: 'Troubleshooting', link: '/guide/troubleshooting' },
          ],
        },
        {
          text: 'Integrations',
          items: [
            { text: 'Godot-AI tools', link: '/guide/godot-ai' },
          ],
        },
        {
          text: 'Reference',
          items: [
            { text: 'Typed query API', link: '/guide/query-api' },
            { text: 'Model API', link: '/guide/model-api' },
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
