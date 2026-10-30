// Hyper-плагин: индикатор HyperLLM в углу терминала, автостарт трея и подключение zsh-стратегии.
const http = require('http');
const path = require('path');
const { execFile } = require('child_process');

const PORT = 8765;
const ZSH_SCRIPT = path.join(__dirname, 'zsh', 'llm-complete.zsh');

// Shell видит путь к скрипту только внутри Hyper — в .zshrc: [[ -n $HYPER_LLM_ZSH ]] && source $HYPER_LLM_ZSH
exports.decorateConfig = (config) => ({ ...config, env: { ...config.env, HYPER_LLM_ZSH: ZSH_SCRIPT } });

// Main-процесс: поднять трей, если установлен и не запущен (open -g на живой app ничего не меняет, паузу не снимает).
exports.onApp = () => execFile('open', ['-g', '-b', 'com.hukopo.hyperllm'], () => {});

const ping = (cb) => {
  const req = http.get({ host: '127.0.0.1', port: PORT, path: '/v1/models', timeout: 1000 }, (res) => {
    res.resume();
    cb(res.statusCode === 200);
  });
  req.on('timeout', () => req.destroy());
  req.on('error', () => cb(false));
};

exports.decorateTerm = (Term, { React }) =>
  class LlmStatusTerm extends React.Component {
    constructor(props) {
      super(props);
      this.state = { up: false };
    }
    componentDidMount() {
      const tick = () => ping((up) => !this.dead && this.state.up !== up && this.setState({ up }));
      tick();
      this.timer = setInterval(tick, 3000);
    }
    componentWillUnmount() {
      this.dead = true;
      clearInterval(this.timer);
    }
    render() {
      const up = this.state.up;
      return React.createElement(
        'div',
        { style: { width: '100%', height: '100%', position: 'relative' } },
        React.createElement(Term, this.props),
        React.createElement('div', {
          title: up ? 'HyperLLM: работает' : 'HyperLLM: недоступен — подсказки только из истории',
          style: {
            position: 'absolute', top: 6, right: 10, width: 8, height: 8, borderRadius: 4, zIndex: 100,
            background: up ? '#a6e3a1' : '#6c7086', opacity: up ? 0.9 : 0.5, pointerEvents: 'none',
          },
        })
      );
    }
  };
