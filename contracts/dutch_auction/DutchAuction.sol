// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

error DutchAuction__NegativeAuctionPrice();
error DutchAuction__AutionExpired();
error DutchAuction__NotEnoughETH();

contract DutchAuction {
    uint private constant DURATION = 7 days;

    IERC721 public immutable nft;
    uint public immutable tokenId;

    address public immutable seller;
    uint public immutable startingPrice;
    uint public immutable startAt;
    uint public immutable expiresAt;
    uint public immutable discountRate;

    constructor(
        uint _startingPrice,
        uint _discountRate,
        address _nft,
        uint _tokenId
    ) {
        seller = payable(msg.sender);
        startingPrice = _startingPrice;
        discountRate = _discountRate;
        startAt = block.timestamp;
        expiresAt = block.timestamp + DURATION;

        // 防止拍卖时间未终止，而价格变为负数
        if (_startingPrice < _discountRate * DURATION) {
            revert DutchAuction__NegativeAuctionPrice();
        }

        nft = IERC721(_nft);
        tokenId = _tokenId;
    }

    function getPrice() public view returns (uint) {
        uint timeElapsed = block.timestamp - startAt;
        uint discount = discountRate * timeElapsed;
        return startingPrice - discount;
    }

    function buy() external payable {
        if (block.timestamp >= expiresAt) {
            revert DutchAuction__AutionExpired();
        }

        uint price = getPrice();
        if (msg.value < price) {
            revert DutchAuction__NotEnoughETH();
        }

        nft.transferFrom(seller, msg.sender, tokenId);
        uint refund = msg.value - price;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
    }
}
