 # ContentCreator Hub

A decentralized Patreon-style platform built on Stacks blockchain that enables content creators to monetize their work through multi-tier subscriptions while providing subscribers with exclusive access to content.

## Overview

ContentCreator Hub is a blockchain-based platform that revolutionizes the creator economy by removing intermediaries and providing direct creator-to-fan relationships. Using Clarity smart contracts on the Stacks blockchain, the platform enables creators to set up subscription tiers with varying token requirements, schedule content releases, and access detailed analytics about their audience.

## Features

### For Creators

- **Profile Management**: Create and manage your creator profile with customizable name and description
- **Multi-tier Subscriptions**: Define multiple subscription tiers with different token requirements and durations
- **Content Scheduling**: Schedule content to be published at specific block heights
- **Creator Analytics**: Access detailed metrics about subscribers and content views
- **Direct Monetization**: Receive tokens directly from subscribers without platform fees

### For Subscribers

- **Exclusive Content Access**: Subscribe to creators and gain access to exclusive content
- **Flexible Subscription Options**: Choose from multiple subscription tiers based on your level of support
- **Automatic Renewals**: Enable auto-renewal for uninterrupted access to creator content
- **Transparent Requirements**: Clear token requirements for each subscription tier

## Technical Architecture

ContentCreator Hub is built using Clarity smart contracts on the Stacks blockchain. The platform utilizes:

- **SIP-010 Token Standard**: Compatible with any SIP-010 compliant fungible token
- **Data Maps**: Efficient storage of creator profiles, subscription tiers, content, and analytics
- **Access Control**: Token-gated content access based on subscription tier
- **Analytics Tracking**: Built-in tracking for subscriber counts and content views

## Smart Contract Functions

### Creator Management

- `register-creator`: Register as a new content creator
- `update-creator-profile`: Update an existing creator profile

### Tier Management

- `create-subscription-tier`: Create a new subscription tier with token requirements

### Subscription Management

- `subscribe-to-creator`: Subscribe to a creator at a specific tier
- `renew-subscription`: Renew an existing subscription
- `cancel-subscription`: Cancel an active subscription

### Content Management

- `create-content`: Create new content with tier-based access control
- `view-content`: Access content if subscription requirements are met

### Read-Only Functions

- `get-creator-profile`: Get details about a creator
- `get-subscription-tier`: Get details about a subscription tier
- `get-subscription-status`: Check subscription status for a user
- `get-content-details`: Get details about content
- `get-content-views`: Get view count for content
- `get-tier-subscribers`: Get subscriber count for a tier
- `can-access-content`: Check if a user can access specific content

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) for local development and testing
- [Stacks Wallet](https://www.hiro.so/wallet) for interacting with the deployed contract

### Deployment

1. Clone the repository:
   ```bash
   git clone https://github.com/ad9924214/ContentCreator-Hub.git
   cd ContentCreator-Hub
   ```

2. Test the contract locally:
   ```bash
   npm test
   ```

### Usage Example

#### For Creators:

1. Register as a creator:
   ```clarity
   (contract-call? .ContentCreator-Hub register-creator "Creator Name" "My creator description")
   ```

2. Create subscription tiers:
   ```clarity
   (contract-call? .ContentCreator-Hub create-subscription-tier u1 u1 "Basic Tier" "Access to basic content" 'SP000...TOKEN u100 u30)
   ```

3. Create content:
   ```clarity
   (contract-call? .ContentCreator-Hub create-content u1 "Exclusive Content" "Description" "https://content-url.com" u1 block-height)
   ```

#### For Subscribers:

1. Subscribe to a creator:
   ```clarity
   (contract-call? .ContentCreator-Hub subscribe-to-creator u1 u1 true 'SP000...TOKEN)
   ```

2. Access content:
   ```clarity
   (contract-call? .ContentCreator-Hub view-content u1)
   ```

## Use Cases

- **Digital Artists**: Sell tiered access to digital art collections
- **Writers/Journalists**: Provide exclusive articles to subscribers
- **Musicians**: Release music early to subscribers at higher tiers
- **Video Creators**: Offer behind-the-scenes content to dedicated fans
- **Podcasters**: Provide ad-free episodes to subscribers

## Security Considerations

- The contract includes authorization checks to ensure only authorized users can perform certain actions
- Subscription expiration is enforced at the contract level
- Content access is strictly controlled based on subscription tier

## Future Enhancements

- NFT integration for exclusive collectibles
- Tipping functionality for one-time support
- Community features for subscriber interaction
- Enhanced analytics dashboard
- Mobile application for easier access

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Contact

Project Link: [https://github.com/ad9924214/ContentCreator-Hub](https://github.com/ad9924214/ContentCreator-Hub)
For any questions or inquiries, please contact [ad9924214@gmail.com](mailto:ad9924214@gmail.com).
