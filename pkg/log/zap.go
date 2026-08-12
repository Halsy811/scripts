package logger

import (
	"os"
	"sync/atomic"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

type Level = zapcore.Level

const (
	DebugLevel = zap.DebugLevel
	InfoLevel  = zap.InfoLevel
	WarnLevel  = zap.WarnLevel
	ErrorLevel = zap.ErrorLevel
	PanicLevel = zap.PanicLevel
	FatalLevel = zap.FatalLevel

	// DisableLog — специальное значение для отключения логирования
	DisableLog = zapcore.InvalidLevel
)

// Logger — скрытая обертка над zap, не экспортирует внутренний *zap.Logger
type Logger struct {
	logger      *zap.Logger
	atomicLevel *zap.AtomicLevel
	disabled    *uint32 // указатель, поэтому копии (From With) имеют один и тот же флаг
}

func (l *Logger) enabled() bool {
	if l.disabled == nil {
		return true
	}
	return atomic.LoadUint32(l.disabled) == 0
}

// SetLevel устанавливает уровень. Если передан DisableLog — логирование отключается.
func (l *Logger) SetLevel(level Level) {
	if l.disabled == nil {
		var zero uint32
		l.disabled = &zero
	}
	if level == DisableLog {
		atomic.StoreUint32(l.disabled, 1)
		return
	}
	// Сначала обновляем уровень, затем включаем логирование,
	// чтобы не допустить короткого окна, когда логирование включено,
	// но уровень ещё не применён.
	l.atomicLevel.SetLevel(level)
	atomic.StoreUint32(l.disabled, 0)
}

// Disable полностью отключает вывод логов
func (l *Logger) Disable() {
	if l.disabled == nil {
		var zero uint32
		l.disabled = &zero
	}
	atomic.StoreUint32(l.disabled, 1)
}

// Enable включает вывод логов (возвращает на текущий уровень)
func (l *Logger) Enable() {
	if l.disabled == nil {
		var zero uint32
		l.disabled = &zero
	}
	atomic.StoreUint32(l.disabled, 0)
}

// With возвращает новый `*Logger` с добавленными полями
func (l *Logger) With(fields ...zap.Field) *Logger {
	nl := l.logger.With(fields...)
	return &Logger{
		logger:      nl,
		atomicLevel: l.atomicLevel,
		disabled:    l.disabled,
	}
}

// Sync вызывает Sync у внутреннего логгера
func (l *Logger) Sync() error {
	if l.logger == nil {
		return nil
	}
	return l.logger.Sync()
}

// Базовые методы логирования с пропуском при отключении
func (l *Logger) Debug(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Debug(msg, fields...)
}
func (l *Logger) Info(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Info(msg, fields...)
}
func (l *Logger) Warn(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Warn(msg, fields...)
}
func (l *Logger) Error(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Error(msg, fields...)
}
func (l *Logger) DPanic(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.DPanic(msg, fields...)
}
func (l *Logger) Panic(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Panic(msg, fields...)
}
func (l *Logger) Fatal(msg string, fields ...zap.Field) {
	if !l.enabled() {
		return
	}
	l.logger.Fatal(msg, fields...)
}

// CreateLoggerConsole создает логгер для консоли. При уровне DisableLog — логирование отключено.
func CreateLoggerConsole(colored bool, level Level) (*Logger, error) {
	actualLevel := level
	disabled := false
	if level == DisableLog {
		actualLevel = InfoLevel
		disabled = true
	}

	al := zap.NewAtomicLevelAt(actualLevel)

	cfg := zap.NewDevelopmentConfig()
	if colored {
		cfg.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	}

	encoder := zapcore.NewConsoleEncoder(cfg.EncoderConfig)
	core := zapcore.NewCore(encoder, zapcore.AddSync(os.Stdout), al)
	l := zap.New(core, zap.AddCaller(), zap.AddStacktrace(zap.ErrorLevel))

	var dv uint32
	if disabled {
		dv = 1
	}
	logger := &Logger{
		logger:      l,
		atomicLevel: &al,
		disabled:    &dv,
	}
	return logger, nil
}

// CreateLoggerFile создает логгер, пишущий в указанный файл
func CreateLoggerFile(file *os.File, level Level) (*Logger, error) {
	writer := zapcore.AddSync(file)

	actualLevel := level
	disabled := false
	if level == DisableLog {
		actualLevel = InfoLevel
		disabled = true
	}

	al := zap.NewAtomicLevelAt(actualLevel)

	core := zapcore.NewCore(
		zapcore.NewJSONEncoder(zap.NewProductionEncoderConfig()),
		writer,
		al,
	)

	loggerInst := zap.New(core)

	var dv uint32
	if disabled {
		dv = 1
	}
	logger := &Logger{
		logger:      loggerInst,
		atomicLevel: &al,
		disabled:    &dv,
	}

	return logger, nil
}
