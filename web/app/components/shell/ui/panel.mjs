import { LitElement } from 'https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm';
import { SHELL_BASE_STYLE } from './styles/base_style.mjs';
import { SHELL_RESPONSIVE_STYLE } from './styles/responsive_style.mjs';
import { SHELL_THEME_STYLE } from './styles/theme_style.mjs';

const SHELL_STYLE_TEXT = [
  SHELL_BASE_STYLE,
  SHELL_RESPONSIVE_STYLE,
  SHELL_THEME_STYLE
].join('\n\n');

class RhdlAppShell extends LitElement {
  createRenderRoot() {
    return this;
  }

  shouldUpdate() {
    return false;
  }

  connectedCallback() {
    super.connectedCallback();
    this.installStyles();
  }

  installStyles() {
    if (this.__shellStylesInstalled) {
      return;
    }
    const style = document.createElement('style');
    style.setAttribute('data-rhdl-app-shell-styles', '1');
    style.textContent = SHELL_STYLE_TEXT;
    this.prepend(style);
    this.__shellStylesInstalled = true;
  }
}

if (!customElements.get('rhdl-app-shell')) {
  customElements.define('rhdl-app-shell', RhdlAppShell);
}
