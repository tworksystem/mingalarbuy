/**
 * WooCommerce Webhook Server
 * Sends FCM notifications when order status changes
 * 
 * Setup:
 * 1. npm install express firebase-admin body-parser
 * 2. Configure Firebase Admin SDK (see below)
 * 3. Run: node webhook_server.js
 * 
 * WooCommerce Configuration:
 * - Webhook URL: http://your-server.com/api/webhook/order-status
 * - Secret Key: Your secret key
 * - Status: Active
 */

const express = require('express');
const admin = require('firebase-admin');
const bodyParser = require('body-parser');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(bodyParser.json());

// Initialize Firebase Admin SDK
// IMPORTANT: Replace with your service account key
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

/**
 * Database: In-memory storage for FCM tokens
 * Replace this with your actual database (MongoDB, MySQL, etc.)
 */
const userTokens = new Map();

/**
 * API: Register/Update FCM Token
 * POST /api/users/register-token
 * Body: { userId: string, fcmToken: string, platform: string }
 */
app.post('/api/users/register-token', async (req, res) => {
  try {
    const { userId, fcmToken, platform } = req.body;

    if (!userId || !fcmToken) {
      return res.status(400).json({
        success: false,
        error: 'userId and fcmToken are required',
      });
    }

    // Store token in database
    if (!userTokens.has(userId)) {
      userTokens.set(userId, []);
    }
    
    const tokens = userTokens.get(userId);
    
    // Remove old tokens and add new one
    const filteredTokens = tokens.filter(
      token => token.platform !== platform || token.token !== fcmToken
    );
    filteredTokens.push({ token: fcmToken, platform: platform || 'android' });
    userTokens.set(userId, filteredTokens);

    console.log(`✅ FCM token registered for user ${userId}: ${fcmToken.substring(0, 20)}...`);

    res.json({
      success: true,
      message: 'FCM token registered successfully',
      userId: userId,
      tokenCount: filteredTokens.length,
    });
  } catch (error) {
    console.error('❌ Error registering token:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * Webhook: WooCommerce Order Status Change
 * POST /api/webhook/order-status
 * This is called by WooCommerce when order status changes
 */
app.post('/api/webhook/order-status', async (req, res) => {
  try {
    const order = req.body;

    // Validate webhook payload
    if (!order || !order.id) {
      console.error('❌ Invalid webhook payload');
      return res.status(400).json({
        success: false,
        error: 'Invalid order data',
      });
    }

    console.log(`📦 Order status webhook received: Order #${order.id}, Status: ${order.status}`);

    // Get customer ID from order
    const customerId = order.customer_id?.toString();
    
    if (!customerId) {
      console.error('❌ No customer ID in order');
      return res.status(400).json({
        success: false,
        error: 'No customer ID found',
      });
    }

    // Get FCM tokens for this customer
    const tokens = userTokens.get(customerId) || [];
    
    if (tokens.length === 0) {
      console.log(`⚠️ No FCM tokens found for customer ${customerId}`);
      return res.json({
        success: true,
        message: 'No tokens to send notification to',
      });
    }

    // Prepare notification
    const statusMessage = getStatusMessage(order.status);
    const total = order.total || '0.00';
    const currency = order.currency || 'USD';

    const notification = {
      title: `Order #${order.id} ${statusMessage}`,
      body: `Your order total is ${currency} ${total}`,
    };

    const data = {
      orderId: order.id.toString(),
      status: order.status,
      total: order.total?.toString() || '0',
      currency: order.currency || 'USD',
      type: 'order_status_update',
      userId: customerId, // PROFESSIONAL SECURITY: Include userId for verification
      user_id: customerId, // Also include user_id for compatibility
    };

    // Send notification to all tokens for this user with retry logic
    const results = [];
    const MAX_RETRIES = 3;
    const RETRY_DELAY = 1000; // 1 second
    
    for (const { token, platform } of tokens) {
      let retryCount = 0;
      let success = false;
      
      while (retryCount < MAX_RETRIES && !success) {
        try {
          const message = {
            token: token,
            notification: notification,
            data: data,
            // Add time-to-live for better delivery
            android: {
              priority: 'high',
              ttl: 3600000, // 1 hour
              notification: {
                channelId: 'order_updates',
                sound: 'default',
                priority: 'high',
                importance: 'high',
                // Enable heads-up notification
                defaultSound: true,
                defaultVibrateTimings: true,
                defaultLightSettings: true,
              },
            },
            apns: {
              headers: {
                'apns-priority': '10', // High priority
              },
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  // Enable critical alert for important updates
                  alert: {
                    title: notification.title,
                    body: notification.body,
                  },
                  'content-available': 1, // Enable background processing
                },
              },
            },
            // Add web push config for better delivery
            webpush: {
              notification: {
                title: notification.title,
                body: notification.body,
                requireInteraction: true, // Keep notification visible
              },
            },
          };

          const response = await admin.messaging().send(message);
          console.log(`✅ Notification sent to ${platform} token: ${token.substring(0, 20)}...`);
          
          results.push({
            platform: platform,
            success: true,
            messageId: response,
            retries: retryCount,
          });
          
          success = true;
        } catch (error) {
          retryCount++;
          
          // Remove invalid tokens immediately (don't retry)
          if (error.code === 'messaging/invalid-registration-token' || 
              error.code === 'messaging/registration-token-not-registered') {
            console.error(`❌ Invalid token detected, removing: ${token.substring(0, 20)}...`);
            const updatedTokens = tokens.filter(t => t.token !== token);
            userTokens.set(customerId, updatedTokens);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount - 1,
            });
            
            break; // Don't retry invalid tokens
          }
          
          // Retry on temporary errors
          if (retryCount < MAX_RETRIES) {
            console.warn(`⚠️ Retry ${retryCount}/${MAX_RETRIES} for token ${token.substring(0, 20)}...: ${error.code}`);
            await new Promise(resolve => setTimeout(resolve, RETRY_DELAY * retryCount)); // Exponential backoff
          } else {
            console.error(`❌ Failed to send notification after ${MAX_RETRIES} retries to token ${token.substring(0, 20)}...:`, error.code);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount,
            });
          }
        }
      }
    }

    console.log(`📤 Sent ${results.filter(r => r.success).length}/${results.length} notifications for order #${order.id}`);

    // Always return success to WooCommerce (even if some notifications failed)
    res.json({
      success: true,
      message: 'Webhook processed',
      orderId: order.id,
      notificationsSent: results.filter(r => r.success).length,
      results: results,
    });
  } catch (error) {
    console.error('❌ Error processing webhook:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * Helper: Get user-friendly status message
 */
function getStatusMessage(status) {
  const statusMap = {
    'pending': 'is being processed',
    'processing': 'is being prepared',
    'on-hold': 'is on hold',
    'completed': 'has been completed',
    'cancelled': 'has been cancelled',
    'refunded': 'has been refunded',
    'failed': 'payment failed',
    'shipped': 'has been shipped',
  };
  
  return statusMap[status] || 'status has been updated';
}

/**
 * API: Get stored tokens (for debugging)
 * GET /api/debug/tokens
 */
app.get('/api/debug/tokens', (req, res) => {
  const debugInfo = {};
  userTokens.forEach((tokens, userId) => {
    debugInfo[userId] = tokens.map(t => ({
      platform: t.platform,
      token: t.token.substring(0, 30) + '...',
      fullToken: t.token, // Include full token for testing
    }));
  });
  
  res.json({
    userCount: userTokens.size,
    totalTokens: Array.from(userTokens.values()).reduce((sum, tokens) => sum + tokens.length, 0),
    tokens: debugInfo,
  });
});

/**
 * API: Test notification for a specific user
 * POST /api/debug/test-notification
 * Body: { userId: string, points?: number }
 */
app.post('/api/debug/test-notification', async (req, res) => {
  try {
    const { userId, points = 100 } = req.body;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        error: 'userId is required',
      });
    }
    
    const customerId = userId.toString();
    const tokens = userTokens.get(customerId) || [];
    
    if (tokens.length === 0) {
      return res.status(404).json({
        success: false,
        error: `No FCM tokens found for user ${customerId}`,
        availableUsers: Array.from(userTokens.keys()),
      });
    }
    
    const notification = {
      title: `🎉 ${points} Test Points Added!`,
      body: `This is a test notification for ${points} points.`,
    };
    
    const data = {
      type: 'points_approved',
      transactionId: '999',
      userId: customerId,
      points: points.toString(),
      currentBalance: '0',
      description: 'Test notification',
    };
    
    const results = [];
    for (const { token, platform } of tokens) {
      try {
        const message = {
          token: token,
          notification: notification,
          data: data,
          android: {
            priority: 'high',
            notification: {
              channelId: 'points_updates',
              sound: 'default',
              priority: 'high',
              importance: 'high',
            },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
                alert: {
                  title: notification.title,
                  body: notification.body,
                },
              },
            },
          },
        };
        
        const response = await admin.messaging().send(message);
        results.push({
          platform: platform,
          success: true,
          messageId: response,
        });
      } catch (error) {
        results.push({
          platform: platform,
          success: false,
          error: error.code || error.message,
        });
      }
    }
    
    res.json({
      success: true,
      message: `Test notification sent to ${results.filter(r => r.success).length}/${results.length} tokens`,
      results: results,
    });
  } catch (error) {
    console.error('❌ Error sending test notification:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * Webhook: Points Transaction Approved
 * POST /api/webhook/points-approved
 * Called by WordPress when admin approves a points transaction
 */
app.post('/api/webhook/points-approved', async (req, res) => {
  try {
    const { userId, transactionId, points, description, currentBalance } = req.body;

    // Validate webhook payload
    if (!userId || !transactionId || points === undefined) {
      console.error('❌ Invalid points approval webhook payload');
      return res.status(400).json({
        success: false,
        error: 'userId, transactionId, and points are required',
      });
    }

    console.log(`🎯 Points approval webhook received: Transaction #${transactionId}, User: ${userId}, Points: ${points}`);

    // Get FCM tokens for this user
    const customerId = userId.toString();
    const tokens = userTokens.get(customerId) || [];
    
    if (tokens.length === 0) {
      console.log(`⚠️ No FCM tokens found for user ${customerId}`);
      return res.json({
        success: true,
        message: 'No tokens to send notification to',
      });
    }

    // Prepare notification
    const notification = {
      title: points > 0 ? `🎉 ${points} Points Added!` : `${Math.abs(points)} Points Updated`,
      body: description || (points > 0 ? `You've received ${points} loyalty points!` : `Your points balance has been updated.`),
    };

    const data = {
      type: 'points_approved',
      transactionId: transactionId.toString(),
      userId: userId.toString(),
      points: points.toString(),
      currentBalance: currentBalance ? currentBalance.toString() : '',
      description: description || '',
    };

    // Send notification to all tokens for this user with retry logic
    const results = [];
    const MAX_RETRIES = 3;
    const RETRY_DELAY = 1000; // 1 second
    
    for (const { token, platform } of tokens) {
      let retryCount = 0;
      let success = false;
      
      while (retryCount < MAX_RETRIES && !success) {
        try {
          const message = {
            token: token,
            notification: notification,
            data: data,
            android: {
              priority: 'high',
              ttl: 3600000, // 1 hour
              notification: {
                channelId: 'points_updates',
                sound: 'default',
                priority: 'high',
                importance: 'high',
                defaultSound: true,
                defaultVibrateTimings: true,
                defaultLightSettings: true,
              },
            },
            apns: {
              headers: {
                'apns-priority': '10', // High priority
              },
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  alert: {
                    title: notification.title,
                    body: notification.body,
                  },
                  'content-available': 1,
                },
              },
            },
            webpush: {
              notification: {
                title: notification.title,
                body: notification.body,
                requireInteraction: true,
              },
            },
          };

          const response = await admin.messaging().send(message);
          console.log(`✅ Points notification sent to ${platform} token: ${token.substring(0, 20)}...`);
          
          results.push({
            platform: platform,
            success: true,
            messageId: response,
            retries: retryCount,
          });
          
          success = true;
        } catch (error) {
          retryCount++;
          
          // Remove invalid tokens immediately
          if (error.code === 'messaging/invalid-registration-token' || 
              error.code === 'messaging/registration-token-not-registered') {
            console.error(`❌ Invalid token detected, removing: ${token.substring(0, 20)}...`);
            const updatedTokens = tokens.filter(t => t.token !== token);
            userTokens.set(customerId, updatedTokens);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount - 1,
            });
            
            break;
          }
          
          // Retry on temporary errors
          if (retryCount < MAX_RETRIES) {
            console.warn(`⚠️ Retry ${retryCount}/${MAX_RETRIES} for token ${token.substring(0, 20)}...: ${error.code}`);
            await new Promise(resolve => setTimeout(resolve, RETRY_DELAY * retryCount));
          } else {
            console.error(`❌ Failed to send notification after ${MAX_RETRIES} retries:`, error.code);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount,
            });
          }
        }
      }
    }

    console.log(`📤 Sent ${results.filter(r => r.success).length}/${results.length} points notifications for transaction #${transactionId}`);

    // Always return success to WordPress (even if some notifications failed)
    res.json({
      success: true,
      message: 'Points approval webhook processed',
      transactionId: transactionId,
      notificationsSent: results.filter(r => r.success).length,
      results: results,
    });
  } catch (error) {
    console.error('❌ Error processing points approval webhook:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * PROFESSIONAL FCM NOTIFICATION: Unified Point Events Webhook
 * POST /api/webhook/points-event
 * Handles all point-related notifications with professional error handling
 * 
 * Supported types:
 * - points_earned: Points earned from reward code, lucky box, etc.
 * - points_approved: Points approved by admin (transaction approved)
 * - points_redeemed: Points redeemed (exchange request created)
 * - exchange_approved: Exchange request approved
 * - exchange_rejected: Exchange request rejected
 * - engagement_points: Points earned from engagement activities
 * - points_adjusted: Points manually adjusted from admin dashboard
 */
app.post('/api/webhook/points-event', async (req, res) => {
  try {
    const { userId, type, transactionId, requestId, points, currentBalance, description, itemType, itemTitle, reason, isPositive } = req.body;

    // Validate required fields
    if (!userId || !type) {
      console.error('❌ Invalid points-event webhook payload');
      return res.status(400).json({
        success: false,
        error: 'userId and type are required',
      });
    }

    console.log(`🎯 Points event webhook received: Type: ${type}, User: ${userId}, Points: ${points || 'N/A'}`);

    // Get FCM tokens for this user
    const customerId = userId.toString();
    const tokens = userTokens.get(customerId) || [];
    
    if (tokens.length === 0) {
      console.log(`⚠️ No FCM tokens found for user ${customerId}`);
      return res.json({
        success: true,
        message: 'No tokens to send notification to',
      });
    }

    // Prepare notification based on type
    const notificationConfig = getPointsNotificationConfig(type, points, description, itemType, itemTitle, reason, isPositive);
    
    if (!notificationConfig) {
      console.error(`❌ Invalid notification type: ${type}`);
      return res.status(400).json({
        success: false,
        error: 'Invalid notification type',
      });
    }

    const notification = {
      title: notificationConfig.title,
      body: notificationConfig.body,
    };

    const data = {
      type: type,
      userId: userId.toString(),
      transactionId: transactionId ? transactionId.toString() : '',
      requestId: requestId ? requestId.toString() : '',
      points: points ? points.toString() : '',
      currentBalance: currentBalance ? currentBalance.toString() : '',
      description: description || '',
      itemType: itemType || '',
      itemTitle: itemTitle || '',
      reason: reason || '',
    };

    // Send notification to all tokens with retry logic
    const results = [];
    const MAX_RETRIES = 3;
    const RETRY_DELAY = 1000;
    
    for (const { token, platform } of tokens) {
      let retryCount = 0;
      let success = false;
      
      while (retryCount < MAX_RETRIES && !success) {
        try {
          const message = {
            token: token,
            notification: notification,
            data: data,
            android: {
              priority: 'high',
              ttl: 3600000, // 1 hour
              notification: {
                channelId: 'points_updates',
                sound: 'default',
                priority: 'high',
                importance: 'high',
                defaultSound: true,
                defaultVibrateTimings: true,
                defaultLightSettings: true,
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
              },
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  alert: {
                    title: notification.title,
                    body: notification.body,
                  },
                  'content-available': 1,
                },
              },
            },
            webpush: {
              notification: {
                title: notification.title,
                body: notification.body,
                requireInteraction: true,
              },
            },
          };

          const response = await admin.messaging().send(message);
          console.log(`✅ ${type} notification sent to ${platform} token: ${token.substring(0, 20)}...`);
          
          results.push({
            platform: platform,
            success: true,
            messageId: response,
            retries: retryCount,
          });
          
          success = true;
        } catch (error) {
          retryCount++;
          
          // Remove invalid tokens immediately
          if (error.code === 'messaging/invalid-registration-token' || 
              error.code === 'messaging/registration-token-not-registered') {
            console.error(`❌ Invalid token detected, removing: ${token.substring(0, 20)}...`);
            const updatedTokens = tokens.filter(t => t.token !== token);
            userTokens.set(customerId, updatedTokens);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount - 1,
            });
            
            break;
          }
          
          // Retry on temporary errors
          if (retryCount < MAX_RETRIES) {
            console.warn(`⚠️ Retry ${retryCount}/${MAX_RETRIES} for token ${token.substring(0, 20)}...: ${error.code}`);
            await new Promise(resolve => setTimeout(resolve, RETRY_DELAY * retryCount));
          } else {
            console.error(`❌ Failed to send notification after ${MAX_RETRIES} retries:`, error.code);
            
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount,
            });
          }
        }
      }
    }

    console.log(`📤 Sent ${results.filter(r => r.success).length}/${results.length} ${type} notifications for user ${userId}`);

    // Always return success to WordPress (even if some notifications failed)
    res.json({
      success: true,
      message: 'Points event webhook processed',
      type: type,
      notificationsSent: results.filter(r => r.success).length,
      results: results,
    });
  } catch (error) {
    console.error('❌ Error processing points event webhook:', error);
    res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * Get notification configuration based on event type
 * @param {string} type - Notification type
 * @param {string|number} points - Points amount
 * @param {string} description - Notification description
 * @param {string} itemType - Item type (for engagement)
 * @param {string} itemTitle - Item title (for engagement)
 * @param {string} reason - Rejection reason (for exchange_rejected)
 * @param {boolean} isPositive - Whether adjustment is positive (for points_adjusted)
 */
function getPointsNotificationConfig(type, points, description, itemType, itemTitle, reason, isPositive) {
  const pointsNum = points ? parseInt(points, 10) : 0;
  
  switch (type) {
    case 'points_earned':
      return {
        title: pointsNum > 0 ? `🎉 Congratulations! ${pointsNum} PNP Earned` : 'Points Balance Updated',
        body: description || (pointsNum > 0 ? `Great news! You've earned ${pointsNum} PNP. Check your balance for details.` : 'Your points balance has been updated.'),
      };
      
    case 'points_approved':
      return {
        title: pointsNum > 0 ? `✅ ${pointsNum} PNP Successfully Approved` : 'Points Request Approved',
        body: description || (pointsNum > 0 ? `Your ${pointsNum} PNP transaction has been approved and added to your account.` : 'Your points request has been approved.'),
      };
      
    case 'points_redeemed':
      return {
        title: '💎 Exchange Request Submitted',
        body: description || (pointsNum > 0 ? `Your exchange request for ${pointsNum} PNP has been submitted and is pending review.` : 'Your exchange request has been submitted and is pending review.'),
      };
      
    case 'exchange_approved':
      return {
        title: '✅ Exchange Request Approved',
        body: description || 'Your exchange request has been approved and is being processed. You will receive your reward shortly.',
      };
      
    case 'exchange_rejected':
      const rejectionMessage = reason 
        ? `Your exchange request was not approved. Reason: ${reason}. Your points have been refunded to your account.`
        : 'Your exchange request was not approved. Your points have been refunded.';
      return {
        title: '⚠️ Exchange Request Update',
        body: description || rejectionMessage,
      };
      
    case 'engagement_points':
      const activityName = itemTitle || itemType || 'this activity';
      return {
        title: pointsNum > 0 ? `🎯 ${pointsNum} PNP from Activity` : 'Activity Points Earned',
        body: description || (pointsNum > 0 ? `Thank you for your participation! You earned ${pointsNum} PNP from ${activityName}.` : 'You earned points from an engagement activity. Check your balance for details.'),
      };
      
    case 'points_adjusted':
      const adjustIsPositive = isPositive === true || isPositive === '1' || isPositive === 1;
      const adjustType = adjustIsPositive ? 'increased' : 'decreased';
      const adjustVerb = adjustIsPositive ? 'added' : 'deducted';
      return {
        title: '📊 Points Balance Adjusted',
        body: description || (pointsNum > 0 ? `Your points balance has been ${adjustType}. ${pointsNum} PNP has been ${adjustVerb}.` : 'Your points balance has been adjusted.'),
      };
      
    default:
      return null;
  }
}

/**
 * Webhook: Reward Updated
 * POST /api/webhook/reward-updated
 * Called by WordPress when admin updates reward value for a user transaction
 */
app.post('/api/webhook/reward-updated', async (req, res) => {
  try {
    const { userId, transactionId, rewardValue, status } = req.body;

    if (!userId || !transactionId) {
      console.error('❌ Invalid reward-updated webhook payload');
      return res.status(400).json({
        success: false,
        error: 'userId and transactionId are required',
      });
    }

    console.log(
      `🏷️ Reward update webhook received: Transaction #${transactionId}, User: ${userId}, Value: ${rewardValue ?? ''}, Status: ${status ?? ''}`
    );

    const customerId = userId.toString();
    const tokens = userTokens.get(customerId) || [];

    if (tokens.length === 0) {
      console.log(`⚠️ No FCM tokens found for user ${customerId}`);
      return res.json({
        success: true,
        message: 'No tokens to send notification to',
      });
    }

    const notification = {
      title: '🎁 Reward Updated',
      body:
        rewardValue && rewardValue.toString().trim().length > 0
          ? `Your reward is updated: ${rewardValue}`
          : 'Your rewards have been updated.',
    };

    const data = {
      type: 'reward_updated',
      transactionId: transactionId.toString(),
      userId: userId.toString(),
      rewardValue: rewardValue ? rewardValue.toString() : '',
      status: status ? status.toString() : '',
    };

    const results = [];
    const MAX_RETRIES = 3;

    for (const { token, platform } of tokens) {
      let retryCount = 0;
      let success = false;

      while (retryCount < MAX_RETRIES && !success) {
        try {
          const message = {
            token: token,
            notification: notification,
            data: data,
            android: {
              priority: 'high',
              ttl: 3600000,
              notification: {
                channelId: 'points_updates',
                sound: 'default',
                priority: 'high',
                importance: 'high',
                defaultSound: true,
                defaultVibrateTimings: true,
                defaultLightSettings: true,
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
              },
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                  alert: {
                    title: notification.title,
                    body: notification.body,
                  },
                  'content-available': 1,
                },
              },
            },
            webpush: {
              notification: {
                title: notification.title,
                body: notification.body,
                requireInteraction: true,
              },
            },
          };

          const response = await admin.messaging().send(message);
          console.log(
            `✅ Reward notification sent to ${platform} token: ${token.substring(0, 20)}...`
          );

          results.push({
            platform: platform,
            success: true,
            messageId: response,
            retries: retryCount,
          });

          success = true;
        } catch (error) {
          retryCount++;

          // Remove invalid tokens immediately (don't retry)
          if (
            error.code === 'messaging/invalid-registration-token' ||
            error.code === 'messaging/registration-token-not-registered'
          ) {
            console.error(`❌ Invalid token detected, removing: ${token.substring(0, 20)}...`);
            const updatedTokens = tokens.filter((t) => t.token !== token);
            userTokens.set(customerId, updatedTokens);

            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount - 1,
            });
            break;
          }

          if (retryCount < MAX_RETRIES) {
            await new Promise((resolve) => setTimeout(resolve, 1000 * retryCount));
          } else {
            results.push({
              platform: platform,
              success: false,
              error: error.code || error.message,
              retries: retryCount,
            });
          }
        }
      }
    }

    return res.json({
      success: true,
      message: `Reward notification sent to ${results.filter((r) => r.success).length}/${results.length} tokens`,
      results,
    });
  } catch (error) {
    console.error('❌ Error sending reward notification:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error',
    });
  }
});

/**
 * API: Health check
 * GET /api/health
 */
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    registeredUsers: userTokens.size,
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Webhook server running on port ${PORT}`);
  console.log(`📦 WooCommerce webhook URL: http://your-server.com:${PORT}/api/webhook/order-status`);
  console.log(`📱 FCM registration URL: http://your-server.com:${PORT}/api/users/register-token`);
});

/**
 * Firebase Admin Service Account Setup:
 * 
 * 1. Go to Firebase Console → Project Settings → Service Accounts
 * 2. Click "Generate new private key"
 * 3. Save as serviceAccountKey.json in this directory
 * 4. Make sure to add serviceAccountKey.json to .gitignore
 * 
 * File structure should be:
 * backend/
 *   ├── webhook_server.js
 *   ├── serviceAccountKey.json
 *   └── package.json
 */

