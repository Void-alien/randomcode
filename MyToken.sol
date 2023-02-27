// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";
import "./ERC2981.sol";
import "./ERC721A.sol";
import "./DefaultOperatorFilterer.sol";

interface IParentContract{
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external returns (address owner);
}

contract MyToken is ERC721A, ERC2981, Ownable,DefaultOperatorFilterer,ReentrancyGuard {
    bytes32 public merkleRootWL=0xe7f8298f87d2ee1929e46697d0f96aab1169087ecf1c383fec654de16742cee4;
    bytes32 public merkleRootGoList=0xe7f8298f87d2ee1929e46697d0f96aab1169087ecf1c383fec654de16742cee4;
    string public baseURI="";
    string public tokenSuffix="";
    string public unrevealedURI="ipfs://QmbUKeeAVcExWbCh4YJdKViHhMMZ7KEbXY2seqM4zELjTe";
    bool public isRevealed = false;
    address public payoutAddress=0x427811A5E90621FA8e54245479Bc24f566817C36;
    uint256 public mintPrice=0.0012 ether;
    uint256 public mintPriceWL=0.0001 ether;
    uint256 public maxTokens = 100;
    uint256 public mintPhase=0;
    uint256 public burnEnabled=0;
    uint256 public zburn=3;
    uint256 public MAX_MINT_PUBLIC = 10;
    uint256 public MAX_MINT_FREE = 1;
    uint256 public MAX_MINT_GOLIST = 3;
    uint256 public MAX_MINT_WHITELIST = 2;
    mapping(address => uint256) public whitelistMintedCount;  
    mapping(address => uint256) public publicMintedCount;  
    mapping(address => uint256) public golistMintedCount; 
    address public MyTokenaddress;

    /**
     * @inheritdoc ERC721A
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return
            ERC721A.supportsInterface(interfaceId)
            || ERC2981.supportsInterface(interfaceId);
    }

    //add events
    event PaymentReleased(address to, uint256 amount);
    event TokenMinted(uint256 tokenId, address owner);


    //constructor
      constructor(address daddr) ERC721A("MyToken", "MyToken") {  
       setRoyalties(payoutAddress,150);
       MyTokenaddress=daddr;
    }

    /* MINTING */
    function goMint(uint256[] memory tokens) external nonReentrant{
        require(burnEnabled == 1,"Cannot Burn Yet");
        require(tokens.length >= zburn, "Need more gold");
        require(tokens.length % zburn == 0, "Wrong amount of tokens to burn");
        uint256 tobeminted=tokens.length / zburn;
        require(totalMinted()+tobeminted <= maxTokens, "Not enough available tokens to mint");

        for (uint256 i = 0; i < tokens.length; i++) {
            address tokenOwner = IParentContract(MyTokenaddress).ownerOf(tokens[i]);
            require(msg.sender == tokenOwner,"Not Owner");
            IParentContract(MyTokenaddress).burn(tokens[i]);
        }
     
        _basicMint(msg.sender,tobeminted);
    }

      function goListMint(uint256 numberOfTokens,bytes32[] calldata _merkleProof) external payable nonReentrant{
        require(mintPhase==1,"goList Mint Phase is not available");
        require(totalMinted()+numberOfTokens <= maxTokens, "Not enough available tokens to mint");
        uint256 walletMintedAmt = golistMintedCount[msg.sender];
        require(walletMintedAmt + numberOfTokens <= MAX_MINT_GOLIST,"Exceeded LIST Allocation");
        bytes32 leaf=keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verifyCalldata(_merkleProof,merkleRootGoList,leaf), "Invalid Proof for GoList");

        if(walletMintedAmt >= MAX_MINT_FREE)
        {
            require(msg.value == (numberOfTokens * mintPriceWL), "Incorrect amount of ETH sent");
        }else{
            uint256 tempAmt = walletMintedAmt + numberOfTokens;
            if(tempAmt > MAX_MINT_FREE)
            {
                tempAmt = tempAmt - MAX_MINT_FREE;
                require(msg.value == (tempAmt * mintPriceWL), "Incorrect amount of ETH sent");

            }
        }
            
        _basicMint(msg.sender, numberOfTokens);
        golistMintedCount[msg.sender] +=numberOfTokens;
     
       
    }

    
      function goMintFromWhiteList(uint256 numberOfTokens,bytes32[] calldata _merkleProof) external payable nonReentrant{
        require(mintPhase==2,"Whitelist Minting is not available");
        require(totalMinted()+numberOfTokens <= maxTokens, "Not enough tokens available to mint");
        require(whitelistMintedCount[msg.sender]+numberOfTokens <= MAX_MINT_WHITELIST,"Exceeded WL Allocation");
        require(msg.value == (numberOfTokens * mintPriceWL), "Incorrect amount of ETH sent");
        bytes32 leaf=keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verifyCalldata(_merkleProof,merkleRootWL,leaf), "Invalid Proof for Whitelist");
        _basicMint(msg.sender, numberOfTokens);
        whitelistMintedCount[msg.sender] +=numberOfTokens;
    }

    function goPublicMint(uint256 numberOfTokens,bytes32[] calldata _merkleProof) external payable nonReentrant{
        require(mintPhase==3,"Public Mint is not available");
        require(msg.sender == tx.origin, "Direct only");
        require(totalMinted()+numberOfTokens <= maxTokens, "Not enough tokens available to mint");
        require(publicMintedCount[msg.sender]+numberOfTokens <=MAX_MINT_PUBLIC,"Exceeded Public Allocation");
        bytes32 leaf=keccak256(abi.encodePacked(msg.sender));
        bool p=MerkleProof.verifyCalldata(_merkleProof,merkleRootWL,leaf);
        if(p){
            require(msg.value == (numberOfTokens * mintPriceWL), "Incorrect amount of ETH sent");
        }else{
            require(msg.value == (numberOfTokens * mintPrice), "Incorrect amount of ETH sent");
        }
        _basicMint(msg.sender, numberOfTokens);
        publicMintedCount[msg.sender]+= numberOfTokens;
    }

    function adminMintBulk(address to,uint256 numberOfTokens) public onlyOwner {
        require(totalMinted()+numberOfTokens <= maxTokens, "Not enough tokens available to mint");      
        _basicMint(to, numberOfTokens);
    }

    function _basicMint(address to, uint256 q) private {
        _safeMint(to, q);
        emit TokenMinted(totalSupply()-1, to);
    }

    //Minting Verifications EXTERNAL Only
    function getWLMintedCountForAddress(address w) external view returns (uint256){
        return whitelistMintedCount[w];
    }

    function getDLMintedCountForAddress(address w) external view returns (uint256){
        return golistMintedCount[w];
    }

    function getPublicMintedCountForAddress(address w) external view returns (uint256){
        return publicMintedCount[w];
    }

    function verifyWLWallet(address a, bytes32[] calldata _merkleProof) external view returns (bool){
        bytes32 leaf=keccak256(abi.encodePacked(a));
        return MerkleProof.verifyCalldata(_merkleProof,merkleRootWL,leaf);
    }

    function totalMinted() public view returns(uint) {
        return _totalMinted();
    }

    //OWNER Setters
    function setMerkleRootWL(bytes32 merk) external onlyOwner {
        merkleRootWL=merk;
    }

    function setMerkleRootGoList(bytes32 merk) external onlyOwner {
        merkleRootGoList=merk;
    }

    function setBurnEnabled(uint256 p) external onlyOwner{
        burnEnabled=p;
    }

    function setMAXPublic(uint256 p) external onlyOwner{
        MAX_MINT_PUBLIC=p;
    }

    function setIsRevealed(bool b) external onlyOwner{
        isRevealed=b;
    }

    function setzBurn(uint256 a) external onlyOwner{
        zburn=a;
    }

    function setMintPrice(uint256 b) external onlyOwner{
        mintPrice=b;
    }

    function setMintPriceWL(uint256 b) external onlyOwner{
        mintPriceWL=b;
    }

    function setMAXWL(uint256 p) external onlyOwner{
        MAX_MINT_WHITELIST=p;
    }

    function setMAXGOLIST(uint256 p) external onlyOwner{
        MAX_MINT_GOLIST=p;
    }

    function setMAXFREE(uint256 p) external onlyOwner{
        MAX_MINT_FREE=p;
    }

    function setMintPhase(uint256 p) external onlyOwner{
        mintPhase=p;
        if(p>=1)
            burnEnabled=1;
        if(p==0)
            burnEnabled=0;
    }

    function setMaxTokens(uint256 p) external onlyOwner{
        maxTokens=p;
    }

    function setMyTokenAddress(address s) external onlyOwner {
        MyTokenaddress=s;
    }

    function setPayoutAddress(address s) external onlyOwner {
        payoutAddress=s;
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function setTokenSuffix(string memory suffix) external onlyOwner {
        tokenSuffix = suffix;
    }

    function setUnrevealedURI(string memory _uri) external onlyOwner {
        unrevealedURI = _uri;
    }

    function setRoyalties(address receiver, uint96 royaltyFraction) public onlyOwner {
        _setDefaultRoyalty(receiver, royaltyFraction);
    }
     
    //balance withdrawal functions
    function withdraw(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        uint256 payment = amount;
        Address.sendValue(payable(payoutAddress), payment);
        emit PaymentReleased(payoutAddress, payment);
    }

    function payAddress(address to, uint256 amount) external onlyOwner{
        require(address(this).balance >= amount, "Insufficient balance");
        uint256 payment = amount;
        Address.sendValue(payable(to), payment);
    }

    //URI
    function tokenURI (uint256 tokenId)
        public
        view
        override(ERC721A)
        returns (string memory)
        {
            require(_exists(tokenId), "URIQueryForNonexistentToken");

            if (!isRevealed) {
                return unrevealedURI;
            }

            return string.concat(baseURI, _toString(tokenId),tokenSuffix);
        }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function _unrevealedURI() internal view virtual returns (string memory) {
        return unrevealedURI;
    }

    function contractURI() public pure returns (string memory) {
          return "ipfs://QmQZBKPVytgCW9menoLFtBBrSHYEUuVSMaVJnzEbAke4Qv";
    }
   
    function version() public pure returns (string memory){
        return ".1";
    }
    
    //returns list of tokens for an owner
    function getTokensOfOwner(address owner) external view virtual returns (uint256[] memory) {
        unchecked {
            uint256 tokenIdsIdx;
            address currOwnershipAddr;
            uint256 tokenIdsLength = balanceOf(owner);
            uint256[] memory tokenIds = new uint256[](tokenIdsLength);
            TokenOwnership memory ownership;
            for (uint256 i = _startTokenId(); tokenIdsIdx != tokenIdsLength; ++i) {
                ownership = _ownershipAt(i);
                if (ownership.burned) {
                    continue;
                }
                if (ownership.addr != address(0)) {
                    currOwnershipAddr = ownership.addr;
                }
                if (currOwnershipAddr == owner) {
                    tokenIds[tokenIdsIdx++] = i;
                }
            }
            return tokenIds;
        }
    }

    //Only token owner or approved can burn
    function burn(uint256 tokenId) public virtual {
        _burn(tokenId, true);
    }

    //OS Overrides
    //OS FILTERER
    function setApprovalForAll(address operator, bool approved) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(address operator, uint256 tokenId) public payable override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }
    function transferFrom(address from, address to, uint256 tokenId)
        public
        payable
             override
        onlyAllowedOperator(from)
    {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId)
        public
        payable
           override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
        public
        payable
          override
        onlyAllowedOperator(from)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}