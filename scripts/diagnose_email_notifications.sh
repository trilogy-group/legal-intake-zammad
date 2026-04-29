#!/bin/bash
# Email Notification Diagnostic Script for Zammad Legal Intake
# Run this on your production server to diagnose email notification issues

set -e

echo "========================================="
echo "Zammad Email Notification Diagnostics"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_DIR="${COMPOSE_DIR:-/path/to/your/legal-intake-iac/compose}"
LOG_LINES="${LOG_LINES:-1000}"

echo "Configuration:"
echo "  Compose Directory: $COMPOSE_DIR"
echo "  Log Lines to Check: $LOG_LINES"
echo ""

# Function to check Docker services
check_services() {
    echo "========================================="
    echo "1. Checking Docker Services Status"
    echo "========================================="
    cd "$COMPOSE_DIR"
    docker compose ps
    echo ""
    
    # Check if scheduler is running (critical for notifications)
    if docker compose ps zammad-scheduler | grep -q "Up"; then
        echo -e "${GREEN}✓ zammad-scheduler is running${NC}"
    else
        echo -e "${RED}✗ zammad-scheduler is NOT running - THIS IS THE PROBLEM!${NC}"
        echo "  Notifications are processed by the scheduler service."
        echo "  Run: docker compose up -d zammad-scheduler"
    fi
    echo ""
}

# Function to check for notification attempts in logs
check_notification_attempts() {
    echo "========================================="
    echo "2. Checking for Notification Attempts"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Looking for 'Send notification to:' messages..."
    COUNT=$(docker compose logs --tail=$LOG_LINES | grep -c "Send notification to:" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $COUNT notification attempt(s)${NC}"
        echo ""
        echo "Recent notification attempts:"
        docker compose logs --tail=$LOG_LINES | grep "Send notification to:" | tail -5
    else
        echo -e "${YELLOW}⚠ No notification attempts found in last $LOG_LINES log lines${NC}"
        echo "  This suggests notifications are not being triggered at all."
    fi
    echo ""
}

# Function to check for email channel configuration
check_email_channel() {
    echo "========================================="
    echo "3. Checking Email Channel Configuration"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Checking for email channel warnings..."
    COUNT=$(docker compose logs --tail=$LOG_LINES | grep -c "Can't find an active 'Email::Notification' channel" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${RED}✗ CRITICAL: Email notification channel is NOT configured!${NC}"
        echo "  Found $COUNT instances of this error."
        echo "  Action: Configure the email notification channel in Zammad Admin → Channels → Email → Notifications"
    else
        echo -e "${GREEN}✓ No email channel errors found${NC}"
    fi
    echo ""
}

# Function to check for SMTP/SES errors
check_smtp_errors() {
    echo "========================================="
    echo "4. Checking for SMTP/SES Errors"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Looking for SMTP/SES connection or authentication errors..."
    docker compose logs --tail=$LOG_LINES | grep -iE "smtp|ses|authentication failed|connection refused|timeout|535|554" | grep -v "websocket" | tail -10
    
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}⚠ Found SMTP/SES errors above${NC}"
    else
        echo -e "${GREEN}✓ No SMTP/SES errors found${NC}"
    fi
    echo ""
}

# Function to check for blocked users
check_blocked_users() {
    echo "========================================="
    echo "5. Checking for Blocked Email Users"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Looking for users blocked due to mail delivery failures..."
    COUNT=$(docker compose logs --tail=$LOG_LINES | grep -c "mail_delivery_failed" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Found $COUNT blocked user notification(s)${NC}"
        docker compose logs --tail=$LOG_LINES | grep "mail_delivery_failed" | tail -5
    else
        echo -e "${GREEN}✓ No blocked users found${NC}"
    fi
    echo ""
}

# Function to check Transaction::Notification processing
check_transaction_processing() {
    echo "========================================="
    echo "6. Checking Transaction::Notification Processing"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Looking for Transaction::Notification backend execution..."
    docker compose logs --tail=$LOG_LINES zammad-scheduler | grep -E "Execute single backend|Transaction::Notification" | tail -10
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Transaction notifications are being processed${NC}"
    else
        echo -e "${YELLOW}⚠ No transaction notification processing found${NC}"
        echo "  This suggests no tickets/comments are triggering notifications."
    fi
    echo ""
}

# Function to check for import mode
check_import_mode() {
    echo "========================================="
    echo "7. Checking Import Mode Status"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Checking if import_mode is enabled (blocks all notifications)..."
    docker compose exec -T zammad-railsserver rails runner "puts 'Import mode: ' + Setting.get('import_mode').to_s" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Import mode check complete${NC}"
        echo "  If 'true', notifications are completely disabled!"
    else
        echo -e "${YELLOW}⚠ Could not check import mode (container may not be running)${NC}"
    fi
    echo ""
}

# Function to check delayed jobs
check_delayed_jobs() {
    echo "========================================="
    echo "8. Checking Delayed Job Status"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Looking for delayed job processing..."
    docker compose logs --tail=$LOG_LINES zammad-scheduler | grep -iE "delayed.*job|worker" | tail -10
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Delayed jobs are being processed${NC}"
    else
        echo -e "${YELLOW}⚠ No delayed job activity found${NC}"
    fi
    echo ""
}

# Function to get recent error summary
error_summary() {
    echo "========================================="
    echo "9. Recent Error Summary"
    echo "========================================="
    cd "$COMPOSE_DIR"
    
    echo "Recent ERROR level logs:"
    docker compose logs --tail=$LOG_LINES | grep -i "ERROR" | tail -15
    echo ""
}

# Function to provide actionable recommendations
recommendations() {
    echo "========================================="
    echo "ACTIONABLE RECOMMENDATIONS"
    echo "========================================="
    echo ""
    echo "Based on common issues, here's what to check:"
    echo ""
    echo "1. ${YELLOW}Check Email Channel Configuration:${NC}"
    echo "   docker compose exec zammad-railsserver rails runner \"puts Channel.find_by(area: 'Email::Notification', active: true).inspect\""
    echo ""
    echo "2. ${YELLOW}Check if import mode is disabled:${NC}"
    echo "   docker compose exec zammad-railsserver rails runner \"puts Setting.get('import_mode')\""
    echo "   (should be: false)"
    echo ""
    echo "3. ${YELLOW}Check a specific ticket's notification history:${NC}"
    echo "   docker compose exec zammad-railsserver rails runner \"puts Ticket.find(TICKET_ID).history_get.select { |h| h['type'] == 'notification' }\""
    echo ""
    echo "4. ${YELLOW}Check user notification preferences:${NC}"
    echo "   docker compose exec zammad-railsserver rails runner \"puts User.find_by(email: 'user@example.com').preferences['notification_config'].inspect\""
    echo ""
    echo "5. ${YELLOW}Monitor notifications in real-time:${NC}"
    echo "   docker compose logs -f --tail=50 | grep -E '(notification|email|mailer)'"
    echo ""
    echo "6. ${YELLOW}Check for state-specific blocking:${NC}"
    echo "   Notifications are BLOCKED for tickets in 'submitted_to_legal' state (by design in app/models/transaction/notification.rb:79-81)"
    echo ""
}

# Main execution
main() {
    if [ ! -d "$COMPOSE_DIR" ]; then
        echo -e "${RED}ERROR: Compose directory not found: $COMPOSE_DIR${NC}"
        echo "Please set COMPOSE_DIR environment variable to your docker-compose.yml location"
        echo "Example: COMPOSE_DIR=/path/to/compose $0"
        exit 1
    fi
    
    check_services
    check_notification_attempts
    check_email_channel
    check_smtp_errors
    check_blocked_users
    check_transaction_processing
    check_import_mode
    check_delayed_jobs
    error_summary
    recommendations
    
    echo ""
    echo "========================================="
    echo "Diagnostic complete!"
    echo "========================================="
}

# Run main function
main
