//SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import 'hardhat/console.sol';

contract Marketplace is ERC1155Holder, Ownable, ReentrancyGuard {
    // ------------------ Variable Declarations ---------------------- //

    /// @notice itemId to keep track of the number of items listed for sale on the marketplace
    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;

    /** 
        @notice Royalties are charged as a percentage of an item's sale price. 
        @dev This value is to be defined in the constructor upon deployment and will accept integers between 0 - 100.
     */
    uint public royalties;

    /// @dev owner of the marketplace declared as msg.sender in the constructor.
    address payable marketplaceOwner;

    mapping(uint => Item) private itemsMapping;

    /// @notice Sets the owner of the Marketplace contract as the contract deployer, and initializes proportion of royalties that will go to the marketplace.
    constructor(uint royalty) {
        marketplaceOwner = payable(msg.sender);
        royalties = royalty;
    }

    /// @notice Item struct to store variables required for items listed on the Marketplace
    struct Item {
        address nftAddress;
        uint tokenId;
        uint itemId;
        address creator;
        address payable seller;
        address payable owner;
        uint price;
        bool isListed;
    }

    // ------------------ Events ---------------------- //

    event ItemListed(
        address indexed nftAddress,
        uint indexed tokenId,
        uint indexed itemId,
        address creator,
        address seller,
        address owner,
        uint price,
        bool isListed
    );

    // ------------------ Mutative Functions ---------------------- //

    /**
        @notice Public function listing existing items in the user's wallet for sale on the marketplace. Passes variables into listItem function to execute the listing.  
        @dev Reverts with an error if listing price is not a positive number. 
        @param nftAddress contract address of the NFT to be listed 
        @param _tokenId tokenId of the NFT to be listed
        @param _quantity number of NFTs to  be listed 
        @param price list price of each listed NFT
    */
    function listItemsForSale(
        address nftAddress,
        uint _tokenId,
        uint _quantity,
        uint price
    ) public {
        require(price > 0, 'Item price must be greater than zero');
        for (uint i = 0; i < _quantity; i++) {
            listItem(nftAddress, _tokenId, price);
        }
    }

    /**
        @notice Internal function with variables passed down from listItemsForSale. Executes listing of item by adding new items into the mapping 
        @dev Transfers the NFT from the owner's wallet to the marketplace. 
        @param nftAddress contract address of the NFT to be listed  
        @param _tokenId tokenId of the NFT to be listed
        @param price list price of each listed NFT
    */
    function listItem(
        address nftAddress,
        uint _tokenId,
        uint price
    ) internal {
        _itemIds.increment();
        uint itemId = _itemIds.current();
        itemsMapping[itemId] = Item(
            nftAddress,
            _tokenId,
            itemId,
            msg.sender,
            payable(msg.sender),
            payable(msg.sender),
            price,
            true
        );

        IERC1155(nftAddress).safeTransferFrom(msg.sender, address(this), _tokenId, 1, '0x00');
        emit ItemListed(nftAddress, _tokenId, itemId, msg.sender, msg.sender, address(0), price, true);
    }

    /**
        @notice Allows buyer to purchase one or more NFTs 
        @dev Transfers the desired quantity of tokens from the marketplace to the buyer 
        @dev Transfer a portion of ether sent by the buyer to the marketplace as royalties. Remaining ether is transferred to the seller. 
        @param nftAddress contract address of the NFT to be purchased
        @param _itemId itemId of the NFT to be purchased 
    */
    function purchaseItem(address nftAddress, uint _itemId) public payable nonReentrant {
        uint price = itemsMapping[_itemId].price;
        uint _tokenId = itemsMapping[_itemId].tokenId;
        bool isForSale = itemsMapping[_itemId].isListed;

        require(isForSale == true, 'Item requested is not for sale.');
        require(msg.value == price, 'Please submit the correct amount of ether.');

        uint royaltiesToMarketplace = ((royalties * msg.value) / 100);
        uint etherToSeller = msg.value - royaltiesToMarketplace;

        IERC1155(nftAddress).safeTransferFrom(address(this), msg.sender, _tokenId, 1, '0x00');
        payable(marketplaceOwner).transfer(royaltiesToMarketplace);
        itemsMapping[_itemId].seller.transfer(etherToSeller);
        itemsMapping[_itemId].owner = payable(msg.sender);
        itemsMapping[_itemId].isListed = false;
    }

    /**
        @notice Allows the owner of the NFT to delist their item 
        @dev Requires the caller to be the owner of the item. Sets the 'isListed' property of the item in the mapping to false. 
        @param _itemId itemId of the NFT to be delisted
    */
    function delistItem(uint _itemId) public {
        address itemOwner = itemsMapping[_itemId].owner;
        require(msg.sender == itemOwner, 'msg sender is not owner of item');
        itemsMapping[_itemId].isListed = false;
    }

    /**
        @notice Allows the owner of the NFT to relist their item. 
        @dev Requires the caller to be the owner of the item. Sets the 'isListed' property of the item in the mapping to true. 
        @param _itemId itemId of the NFT to be relisted
    */
    function relistItem(uint _itemId) public {
        require(msg.sender == itemsMapping[_itemId].owner, 'msg sender is not owner of item');
        itemsMapping[_itemId].isListed = true;
    }

    // ------------------ Read Functions ---------------------- //

    function getItemPrice(uint _itemId) public view returns (uint price) {
        return itemsMapping[_itemId].price;
    }

    function getItemById(uint _itemId) public view returns (Item memory) {
        return itemsMapping[_itemId];
    }

    function getListedItems() public view returns (Item[] memory) {
        uint totalItemCount = _itemIds.current();
        uint itemsListedCount = 0;
        uint resultItemId = 0;

        // && itemsMapping[i+1].owner != msg.sender

        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].isListed == true && itemsMapping[i+1].owner != msg.sender) {
                itemsListedCount++;
            }
        }

        Item[] memory listedItems = new Item[](itemsListedCount);
        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].isListed == true && itemsMapping[i+1].owner != msg.sender) {
                uint thisItemId = itemsMapping[i + 1].itemId;
                Item storage thisItem = itemsMapping[thisItemId];
                listedItems[resultItemId] = thisItem;
                resultItemId++;
            }
        }
        return listedItems;
    }

    function getItemsOwned() public view returns (Item[] memory) {
        uint totalItemCount = _itemIds.current();
        uint myItemsCount = 0;
        uint resultItemId = 0;

        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].owner == msg.sender) {
                myItemsCount++;
            }
        }

        Item[] memory ownedItems = new Item[](myItemsCount);
        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].owner == msg.sender) {
                uint thisItemId = itemsMapping[i + 1].itemId;
                Item storage thisItem = itemsMapping[thisItemId];
                ownedItems[resultItemId] = thisItem;
                resultItemId++;
            }
        }
        return ownedItems;
    }

    function getItemsCreated() public view returns (Item[] memory) {
        uint totalItemCount = _itemIds.current();
        uint creationCount = 0;

        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].creator == msg.sender) {
                creationCount++;
            }
        }

        Item[] memory createdItems = new Item[](creationCount);
        for (uint i = 0; i < totalItemCount; i++) {
            if (itemsMapping[i + 1].creator == msg.sender) {
                uint thisItemId = itemsMapping[i + 1].itemId;
                Item storage thisItem = itemsMapping[thisItemId];
                createdItems[i] = thisItem;
            }
        }
        return createdItems;
    }
}
