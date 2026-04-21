FROM node:20-alpine

WORKDIR /app

# Copy dependency manifests first for layer caching
COPY package.json package-lock.json ./

RUN npm install

# Copy the rest of the source
COPY . .

EXPOSE 3000

CMD ["npm", "run", "dev"]
