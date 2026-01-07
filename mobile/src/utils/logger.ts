import { Config } from '@config';

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  message: string;
  data?: any;
  error?: Error;
}

class Logger {
  private logLevel: LogLevel;
  private logs: LogEntry[] = [];
  private maxLogs = 100;

  constructor(level: LogLevel = 'debug') {
    this.logLevel = level;
  }

  setLevel(level: LogLevel) {
    this.logLevel = level;
  }

  private shouldLog(level: LogLevel): boolean {
    const levels: LogLevel[] = ['debug', 'info', 'warn', 'error'];
    const currentIndex = levels.indexOf(this.logLevel);
    const messageIndex = levels.indexOf(level);
    return messageIndex >= currentIndex;
  }

  private addLog(entry: LogEntry) {
    this.logs.push(entry);
    if (this.logs.length > this.maxLogs) {
      this.logs.shift();
    }
  }

  private formatMessage(message: string, data?: any): string {
    let formatted = message;
    if (data) {
      try {
        formatted += ' ' + JSON.stringify(data);
      } catch (e) {
        formatted += ' [Complex Object]';
      }
    }
    return formatted;
  }

  debug(message: string, data?: any) {
    if (!this.shouldLog('debug')) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'debug',
      message,
      data,
    };

    this.addLog(entry);
    console.log(`[DEBUG] ${this.formatMessage(message, data)}`);
  }

  info(message: string, data?: any) {
    if (!this.shouldLog('info')) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'info',
      message,
      data,
    };

    this.addLog(entry);
    console.log(`[INFO] ${this.formatMessage(message, data)}`);
  }

  warn(message: string, data?: any) {
    if (!this.shouldLog('warn')) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'warn',
      message,
      data,
    };

    this.addLog(entry);
    console.warn(`[WARN] ${this.formatMessage(message, data)}`);
  }

  error(message: string, error?: Error | any, data?: any) {
    if (!this.shouldLog('error')) return;

    let errorObj: Error | undefined;
    if (error instanceof Error) {
      errorObj = error;
    } else if (typeof error === 'string') {
      errorObj = new Error(error);
    }

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: 'error',
      message,
      data,
      error: errorObj,
    };

    this.addLog(entry);
    console.error(`[ERROR] ${this.formatMessage(message, data)}`, errorObj);
  }

  getLogs(level?: LogLevel): LogEntry[] {
    if (!level) {
      return this.logs;
    }
    return this.logs.filter((log) => log.level === level);
  }

  clearLogs() {
    this.logs = [];
  }

  exportLogs(): string {
    return JSON.stringify(this.logs, null, 2);
  }
}

// Create singleton instance
export const logger = new Logger(Config.logging.level);

// Export for convenience
export const log = {
  debug: (message: string, data?: any) => logger.debug(message, data),
  info: (message: string, data?: any) => logger.info(message, data),
  warn: (message: string, data?: any) => logger.warn(message, data),
  error: (message: string, error?: Error | any, data?: any) =>
    logger.error(message, error, data),
  getLogs: () => logger.getLogs(),
  clearLogs: () => logger.clearLogs(),
  exportLogs: () => logger.exportLogs(),
};
