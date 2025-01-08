#!/bin/bash

# Переменные Cups
CUPS_CONF="/etc/cups/cupsd.conf"
PDF_PRINTER_NAME="Virtual_PDF_Printer"

#CUPS
# Установка необходимых пакетов
echo "Устанавливаем CUPS и необходимые модули..."
yum install -y cups cups-pdf || {
    echo "Ошибка: Не удалось установить пакеты. Проверьте подключение к репозиторию." >&2
    exit 1
}
# Запуск службы CUPS
echo "Запускаем службу CUPS..."
systemctl enable cups
systemctl start cups
# Настройка виртуального PDF-принтера
echo "Настраиваем виртуальный PDF-принтер..."
lpadmin -p "$PDF_PRINTER_NAME" -E -v cups-pdf:/ -m drv:///sample.drv/generic.ppd || {
    echo "Ошибка: Не удалось добавить принтер." >&2
    exit 1
}
lpadmin -d "$PDF_PRINTER_NAME"
echo "Принтер $PDF_PRINTER_NAME успешно добавлен."
# Настройка веб-интерфейса и удаленного администрирования
echo "Настраиваем веб-интерфейс и удаленное администрирование..."
if grep -q "^Port 631" "$CUPS_CONF"; then
    echo "Веб-интерфейс уже настроен."
else
    sed -i 's/^Listen localhost:631/Port 631/' "$CUPS_CONF" || {
    echo "Ошибка: Не удалось изменить $CUPS_CONF." >&2
    exit 1
}
fi
sed -i 's/<Location \/>/<Location \/>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin>/<Location \/admin>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin\/log>/<Location \/admin\/log>\n  Allow All\n/g' $CUPS_CONF
sed -i 's/<Location \/admin\/conf>/<Location \/admin\/conf>\n  Allow All\n/g' $CUPS_CONF
# Перезапуск службы CUPS
echo "Перезапускаем службу CUPS для применения изменений..."
systemctl restart cups
# Проверка статуса
systemctl status cups --no-pager
if [ $? -eq 0 ]; then
    echo "CUPS успешно настроен и запущен."
    echo "Веб-интерфейс доступен по адресу: http://<IP-адрес-сервера>:631"
else
    echo "Ошибка: Не удалось запустить CUPS." >&2
    exit 1
fi

echo "Настройка завершена."